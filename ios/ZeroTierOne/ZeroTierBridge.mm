#import "ZeroTierBridge.h"
#include <string>
#include <mutex>
#include <thread>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <map>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/select.h>
#include <errno.h>

#include <ZeroTierOne.h>
#include <node/Identity.hpp>
#include <node/Utils.hpp>

#import <Network/Network.h>

static ZeroTierBridge *s_sharedBridge = nil;
static std::mutex s_nodeMutex;
static ZT_Node *s_node = nullptr;
static std::atomic<bool> s_nodeRunning(false);
static std::atomic<bool> s_nodeOnline(false);
static std::thread *s_nodeThread = nullptr;
static volatile int64_t s_nextBackgroundTaskDeadline = 0;
static NSString *s_dataPath = nil;
static NSMutableArray<NSString *> *s_logEntries = nil;
static std::mutex s_logMutex;
static std::atomic<int64_t> s_lastSendCount(0);
static std::atomic<int64_t> s_lastRecvCount(0);
static std::atomic<int64_t> s_lastSendFailCount(0);

static nw_listener_t s_listener4 = nil;
static nw_listener_t s_listener6 = nil;
static int s_localPort4 = 0;
static int s_localPort6 = 0;
static std::mutex s_connMutex;
static std::map<uint64_t, nw_connection_t> s_connections;

static void ztLog(NSString *msg) {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                       dateStyle:NSDateFormatterNoStyle
                                                       timeStyle:NSDateFormatterMediumStyle];
    NSString *entry = [NSString stringWithFormat:@"[%@] %@", timestamp, msg];
    {
        std::lock_guard<std::mutex> lock(s_logMutex);
        if (!s_logEntries) s_logEntries = [NSMutableArray new];
        [s_logEntries addObject:entry];
        if (s_logEntries.count > 500) [s_logEntries removeObjectAtIndex:0];
    }
    NSLog(@"[ZT] %@", msg);
    if (s_sharedBridge) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (s_sharedBridge.onLogUpdate) s_sharedBridge.onLogUpdate();
        });
    }
}

static NSString *sockAddrToString(const struct sockaddr_storage *addr) {
    char buf[INET6_ADDRSTRLEN] = {0};
    uint16_t port = 0;
    if (addr->ss_family == AF_INET) {
        const struct sockaddr_in *sin = (const struct sockaddr_in *)addr;
        inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf));
        port = ntohs(sin->sin_port);
    } else if (addr->ss_family == AF_INET6) {
        const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)addr;
        inet_ntop(AF_INET6, &sin6->sin6_addr, buf, sizeof(buf));
        port = ntohs(sin6->sin6_port);
    }
    return [NSString stringWithFormat:@"%s:%u", buf, port];
}

static uint64_t addrKey(const struct sockaddr_storage *addr) {
    if (addr->ss_family == AF_INET) {
        const struct sockaddr_in *sin = (const struct sockaddr_in *)addr;
        return ((uint64_t)sin->sin_addr.s_addr << 16) | sin->sin_port;
    } else if (addr->ss_family == AF_INET6) {
        const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)addr;
        uint64_t h = 0;
        for (int i = 0; i < 16; i++) h = h * 31 + sin6->sin6_addr.s6_addr[i];
        return h ^ sin6->sin6_port;
    }
    return 0;
}

static nw_connection_t getOrCreateConnection(const struct sockaddr_storage *remoteAddr) {
    uint64_t key = addrKey(remoteAddr);
    {
        std::lock_guard<std::mutex> lock(s_connMutex);
        auto it = s_connections.find(key);
        if (it != s_connections.end()) {
            return it->second;
        }
    }

    NSString *hostStr = nil;
    uint16_t port = 0;
    bool isV6 = false;

    if (remoteAddr->ss_family == AF_INET) {
        const struct sockaddr_in *sin = (const struct sockaddr_in *)remoteAddr;
        char buf[INET6_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf));
        hostStr = [NSString stringWithUTF8String:buf];
        port = ntohs(sin->sin_port);
    } else if (remoteAddr->ss_family == AF_INET6) {
        const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)remoteAddr;
        char buf[INET6_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET6, &sin6->sin6_addr, buf, sizeof(buf));
        hostStr = [NSString stringWithUTF8String:buf];
        port = ntohs(sin6->sin6_port);
        isV6 = true;
    } else {
        return nil;
    }

    nw_endpoint_t remoteEndpoint = nw_endpoint_create_host([hostStr UTF8String],
                                                            [NSString stringWithFormat:@"%u", port].UTF8String);
    nw_parameters_t params = nw_parameters_create_secure_udp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );
    nw_parameters_set_reuse_local_address(params, true);

    if (isV6 && s_localPort6 > 0) {
        char addr6Str[INET6_ADDRSTRLEN] = "::";
        nw_endpoint_t localEndpoint = nw_endpoint_create_host(addr6Str,
                                                               [NSString stringWithFormat:@"%d", s_localPort6].UTF8String);
        nw_parameters_set_local_endpoint(params, localEndpoint);
    } else if (!isV6 && s_localPort4 > 0) {
        char addr4Str[INET_ADDRSTRLEN] = "0.0.0.0";
        nw_endpoint_t localEndpoint = nw_endpoint_create_host(addr4Str,
                                                               [NSString stringWithFormat:@"%d", s_localPort4].UTF8String);
        nw_parameters_set_local_endpoint(params, localEndpoint);
    }

    nw_connection_t conn = nw_connection_create(remoteEndpoint, params);
    if (!conn) {
        ztLog([NSString stringWithFormat:@"NW: failed to create connection to %@:%u", hostStr, port]);
        return nil;
    }

    nw_connection_set_queue(conn, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    nw_connection_start(conn);

    {
        std::lock_guard<std::mutex> lock(s_connMutex);
        s_connections[key] = conn;
    }

    ztLog([NSString stringWithFormat:@"NW: created connection to %@:%u (v%s)", hostStr, port, isV6 ? "6" : "4"]);
    return conn;
}

static void receiveFromListener(nw_connection_t conn) {
    nw_connection_receive(conn, 1, ZT_MAX_PHYSMTU, ^(dispatch_data_t content, nw_content_context_t context,
                                                        bool is_complete, nw_error_t recvError) {
        if (recvError) {
            nw_error_domain_t errDomain = nw_error_get_error_domain(recvError);
            int errCode = (int)nw_error_get_error_code(recvError);
            if (errDomain != nw_error_domain_posix || errCode != EAGAIN) {
                ztLog([NSString stringWithFormat:@"NW recv error: domain=%d code=%d", (int)errDomain, errCode]);
            }
        }
        if (content) {
            const uint8_t *bytes = NULL;
            size_t len = 0;
            dispatch_data_t mapped = dispatch_data_create_map(content, (const void **)&bytes, &len);
            if (bytes && len > 0) {
                s_lastRecvCount++;

                nw_path_t path = nw_connection_copy_current_path(conn);
                nw_endpoint_t remote = path ? nw_path_copy_effective_remote_endpoint(path) : nil;

                char addrBuf[INET6_ADDRSTRLEN] = {0};
                uint16_t rPort = 0;
                if (remote) {
                    const struct sockaddr *sa = nw_endpoint_get_address(remote);
                    if (sa && sa->sa_family == AF_INET) {
                        const struct sockaddr_in *sin = (const struct sockaddr_in *)sa;
                        inet_ntop(AF_INET, &sin->sin_addr, addrBuf, sizeof(addrBuf));
                        rPort = ntohs(sin->sin_port);
                    } else if (sa && sa->sa_family == AF_INET6) {
                        const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)sa;
                        inet_ntop(AF_INET6, &sin6->sin6_addr, addrBuf, sizeof(addrBuf));
                        rPort = ntohs(sin6->sin6_port);
                    }
                }

                ztLog([NSString stringWithFormat:@"RX %zu bytes from %s:%u", len, addrBuf, rPort]);

                int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
                int64_t localSock = (remote && nw_endpoint_get_address(remote) &&
                                     nw_endpoint_get_address(remote)->sa_family == AF_INET6) ? s_localPort6 : s_localPort4;

                struct sockaddr_storage fromAddr;
                memset(&fromAddr, 0, sizeof(fromAddr));
                if (remote) {
                    const struct sockaddr *sa = nw_endpoint_get_address(remote);
                    if (sa) memcpy(&fromAddr, sa, sa->sa_len);
                }

                std::lock_guard<std::mutex> lock(s_nodeMutex);
                if (s_node && fromAddr.ss_family != 0) {
                    uint8_t *buf = (uint8_t *)malloc(len);
                    memcpy(buf, bytes, len);
                    ZT_Node_processWirePacket(s_node, nullptr, now, localSock, &fromAddr, buf, (unsigned int)len, &s_nextBackgroundTaskDeadline);
                    free(buf);
                }
            }
        }
        if (!is_complete && s_nodeRunning) {
            receiveFromListener(conn);
        }
    });
}

static void statePutFunction(ZT_Node *node, void *uptr, void *tptr,
                              enum ZT_StateObjectType type, const uint64_t id[2],
                              const void *data, int len) {
    NSString *dir = s_dataPath;
    if (!dir) return;

    NSString *filename = nil;
    switch (type) {
        case ZT_STATE_OBJECT_IDENTITY_SECRET: filename = @"identity.secret"; break;
        case ZT_STATE_OBJECT_IDENTITY_PUBLIC: filename = @"identity.public"; break;
        case ZT_STATE_OBJECT_PLANET: filename = @"planet"; break;
        case ZT_STATE_OBJECT_MOON:
            filename = [NSString stringWithFormat:@"moons.d/%.16llx.moon", id[0]]; break;
        case ZT_STATE_OBJECT_NETWORK_CONFIG:
            filename = [NSString stringWithFormat:@"networks.d/%.16llx.conf", id[0]]; break;
        case ZT_STATE_OBJECT_PEER:
            filename = [NSString stringWithFormat:@"peers.d/%.16llx", id[0]]; break;
        default: return;
    }

    NSString *fullPath = [dir stringByAppendingPathComponent:filename];
    NSString *parentDir = [fullPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];

    if (len < 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
        ztLog([NSString stringWithFormat:@"DEL %@", filename]);
    } else if (data && len > 0) {
        NSData *nsData = [NSData dataWithBytes:data length:(NSUInteger)len];
        [nsData writeToFile:fullPath atomically:YES];
        ztLog([NSString stringWithFormat:@"PUT %@ (%d bytes)", filename, len]);
    }
}

static int stateGetFunction(ZT_Node *node, void *uptr, void *tptr,
                             enum ZT_StateObjectType type, const uint64_t id[2],
                             void *data, unsigned int len) {
    NSString *dir = s_dataPath;
    if (!dir) return -1;

    NSString *filename = nil;
    switch (type) {
        case ZT_STATE_OBJECT_IDENTITY_SECRET: filename = @"identity.secret"; break;
        case ZT_STATE_OBJECT_IDENTITY_PUBLIC: filename = @"identity.public"; break;
        case ZT_STATE_OBJECT_PLANET: filename = @"planet"; break;
        case ZT_STATE_OBJECT_MOON:
            filename = [NSString stringWithFormat:@"moons.d/%.16llx.moon", id[0]]; break;
        case ZT_STATE_OBJECT_NETWORK_CONFIG:
            filename = [NSString stringWithFormat:@"networks.d/%.16llx.conf", id[0]]; break;
        case ZT_STATE_OBJECT_PEER:
            filename = [NSString stringWithFormat:@"peers.d/%.16llx", id[0]]; break;
        default: return -1;
    }

    NSString *fullPath = [dir stringByAppendingPathComponent:filename];
    NSData *nsData = [NSData dataWithContentsOfFile:fullPath];
    if (!nsData || nsData.length == 0) return -1;
    if (nsData.length > len) return -1;

    memcpy(data, nsData.bytes, nsData.length);
    return (int)nsData.length;
}

static int wirePacketSendFunction(ZT_Node *node, void *uptr, void *tptr,
                                   int64_t localSocket,
                                   const struct sockaddr_storage *remoteAddress,
                                   const void *packetData, unsigned int packetLength,
                                   unsigned int ttl) {
    NSString *addrStr = sockAddrToString(remoteAddress);

    nw_connection_t conn = getOrCreateConnection(remoteAddress);
    if (!conn) {
        s_lastSendFailCount++;
        ztLog([NSString stringWithFormat:@"TX FAIL %u bytes -> %@ (no NW connection)", packetLength, addrStr]);
        return -1;
    }

    dispatch_data_t sendData = dispatch_data_create(packetData, packetLength, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    nw_connection_send(conn, sendData, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
        if (sendError) {
            nw_error_domain_t sendErrDomain = nw_error_get_error_domain(sendError);
            int sendErrCode = (int)nw_error_get_error_code(sendError);
            s_lastSendFailCount++;
            ztLog([NSString stringWithFormat:@"TX FAIL %u bytes -> %@ domain=%d code=%d", packetLength, addrStr, (int)sendErrDomain, sendErrCode]);
        } else {
            s_lastSendCount++;
            ztLog([NSString stringWithFormat:@"TX OK %u bytes -> %@", packetLength, addrStr]);
        }
    });

    return 0;
}

static void virtualNetworkFrameFunction(ZT_Node *node, void *uptr, void *tptr,
                                         uint64_t nwid, void **nuptr,
                                         uint64_t sourceMac, uint64_t destMac,
                                         unsigned int etherType, unsigned int vlanId,
                                         const void *frameData, unsigned int frameLength) {
}

static int virtualNetworkConfigFunction(ZT_Node *node, void *uptr, void *tptr,
                                          uint64_t nwid, void **nuptr,
                                          enum ZT_VirtualNetworkConfigOperation op,
                                          const ZT_VirtualNetworkConfig *config) {
    const char *opStr = "UNKNOWN";
    switch (op) {
        case ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_UP: opStr = "UP"; break;
        case ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_CONFIG_UPDATE: opStr = "CONFIG_UPDATE"; break;
        case ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_DESTROY: opStr = "DESTROY"; break;
        case ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_DOWN: opStr = "DOWN"; break;
    }
    ztLog([NSString stringWithFormat:@"NET CONFIG: nwid=%.16llx op=%s name=%s managed=%u", nwid, opStr, config->name, config->assignedAddressCount]);

    if (s_sharedBridge) {
        dispatch_async(dispatch_get_main_queue(), ^{
            s_sharedBridge.connected = (op == ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_UP || op == ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_CONFIG_UPDATE);
            if (s_sharedBridge.onStatusChange) {
                s_sharedBridge.onStatusChange(s_sharedBridge.connected);
            }
        });
    }
    return 0;
}

static void eventCallback(ZT_Node *node, void *uptr, void *tptr,
                           enum ZT_Event event, const void *metaData) {
    const char *eventName = "UNKNOWN";
    switch (event) {
        case ZT_EVENT_UP: eventName = "UP"; break;
        case ZT_EVENT_OFFLINE: eventName = "OFFLINE"; break;
        case ZT_EVENT_ONLINE: eventName = "ONLINE"; break;
        case ZT_EVENT_DOWN: eventName = "DOWN"; break;
        case ZT_EVENT_FATAL_ERROR_IDENTITY_COLLISION: eventName = "FATAL_ERROR_ID_COLLISION"; break;
        case ZT_EVENT_TRACE: eventName = "TRACE"; break;
        case ZT_EVENT_USER_MESSAGE: eventName = "USER_MESSAGE"; break;
        case ZT_EVENT_REMOTE_TRACE: eventName = "REMOTE_TRACE"; break;
        default: break;
    }

    ztLog([NSString stringWithFormat:@"EVENT: %s", eventName]);

    switch (event) {
        case ZT_EVENT_ONLINE:
            s_nodeOnline = true;
            if (s_sharedBridge) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s_sharedBridge.onOnlineStatusChange) s_sharedBridge.onOnlineStatusChange(YES);
                });
            }
            break;
        case ZT_EVENT_OFFLINE:
            s_nodeOnline = false;
            if (s_sharedBridge) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s_sharedBridge.onOnlineStatusChange) s_sharedBridge.onOnlineStatusChange(NO);
                });
            }
            break;
        case ZT_EVENT_FATAL_ERROR_IDENTITY_COLLISION:
            ztLog(@"FATAL ERROR: Identity collision! Another node has the same address.");
            break;
        case ZT_EVENT_REMOTE_TRACE: {
            const ZT_RemoteTrace *rt = (const ZT_RemoteTrace *)metaData;
            if (rt) {
                ztLog([NSString stringWithFormat:@"REMOTE TRACE: from=%.10llx len=%u", rt->origin, rt->len]);
            }
            break;
        }
        default:
            break;
    }
}

static void logNodeStatus() {
    if (!s_node) return;
    ZT_NodeStatus status;
    memset(&status, 0, sizeof(status));
    ZT_Node_status(s_node, &status);
    char addrBuf[11] = {0};
    ZeroTier::Address(status.address).toString(addrBuf);
    ztLog([NSString stringWithFormat:@"STATUS: addr=%s online=%d", addrBuf, status.online]);

    ZT_PeerList *pl = ZT_Node_peers(s_node);
    if (pl) {
        ztLog([NSString stringWithFormat:@"PEERS: %lu total", (unsigned long)pl->peerCount]);
        for (unsigned int i = 0; i < pl->peerCount && i < 10; i++) {
            ZT_Peer *p = &pl->peers[i];
            char pAddr[11] = {0};
            ZeroTier::Address(p->address).toString(pAddr);
            ztLog([NSString stringWithFormat:@"  PEER %s: latency=%d paths=%u ver=%u.%u.%u",
                   pAddr, p->latency, p->pathCount,
                   p->versionMajor, p->versionMinor, p->versionRev]);
            for (unsigned int j = 0; j < p->pathCount && j < 4; j++) {
                ztLog([NSString stringWithFormat:@"    PATH: %@ pref=%d",
                       sockAddrToString(&p->paths[j].address), p->paths[j].preferred]);
            }
        }
        ZT_Node_freeQueryResult(s_node, pl);
    } else {
        ztLog(@"PEERS: none");
    }

    ztLog([NSString stringWithFormat:@"STATS: sent=%lld recv=%lld sendFail=%lld",
           s_lastSendCount.load(), s_lastRecvCount.load(), s_lastSendFailCount.load()]);
}

static void nodeThreadFunc() {
    ztLog(@"Node thread started");
    int64_t lastStatusLog = 0;
    int bgTaskCount = 0;

    while (s_nodeRunning) {
        int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);

        {
            std::lock_guard<std::mutex> lock(s_nodeMutex);
            if (s_node) {
                enum ZT_ResultCode bgRc = ZT_Node_processBackgroundTasks(s_node, nullptr, now, &s_nextBackgroundTaskDeadline);
                bgTaskCount++;
                if (bgRc != ZT_RESULT_OK) {
                    ztLog([NSString stringWithFormat:@"processBackgroundTasks error: %d", (int)bgRc]);
                }
                if (bgTaskCount % 300 == 0) {
                    ztLog([NSString stringWithFormat:@"BG task #%d running", bgTaskCount]);
                }
            }
        }

        if (now - lastStatusLog >= 15000 && s_node) {
            lastStatusLog = now;
            logNodeStatus();
        }

        int64_t sleepUntil = s_nextBackgroundTaskDeadline;
        int64_t sleepMs = (sleepUntil > 0 && sleepUntil > now) ? (sleepUntil - now) : 100;
        if (sleepMs > 500) sleepMs = 500;
        if (sleepMs < 10) sleepMs = 10;

        std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
    }

    ztLog(@"Node thread stopped");
}

@implementation ZeroTierBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _connected = NO;
        s_sharedBridge = self;
        s_logEntries = [NSMutableArray new];

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = paths.firstObject;
        s_dataPath = [docs stringByAppendingPathComponent:@"zerotier"];
        [[NSFileManager defaultManager] createDirectoryAtPath:s_dataPath withIntermediateDirectories:YES attributes:nil error:nil];

        ztLog([NSString stringWithFormat:@"Data path: %@", s_dataPath]);

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *planetPath = [s_dataPath stringByAppendingPathComponent:@"planet"];
        if ([fm fileExistsAtPath:planetPath]) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:planetPath error:nil];
            ztLog([NSString stringWithFormat:@"Planet file exists: %lu bytes", (unsigned long)[attrs fileSize]]);
        } else {
            ztLog(@"No cached planet file (will use built-in defaults)");
        }

        NSString *idSecPath = [s_dataPath stringByAppendingPathComponent:@"identity.secret"];
        if ([fm fileExistsAtPath:idSecPath]) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:idSecPath error:nil];
            ztLog([NSString stringWithFormat:@"Identity file exists: %lu bytes", (unsigned long)[attrs fileSize]]);
        } else {
            ztLog(@"No existing identity (will generate new one)");
        }
    }
    return self;
}

- (NSString *)nodeId {
    if (s_node) {
        uint64_t addr = ZT_Node_address(s_node);
        if (addr != 0) {
            char buf[11] = {0};
            ZeroTier::Address(addr).toString(buf);
            return [NSString stringWithUTF8String:buf];
        }
    }

    NSString *pubPath = [s_dataPath stringByAppendingPathComponent:@"identity.public"];
    NSData *data = [NSData dataWithContentsOfFile:pubPath];
    if (data && data.length > 0) {
        NSString *pubStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (pubStr.length > 0) {
            ZeroTier::Identity id;
            if (id.fromString([pubStr UTF8String])) {
                char buf[11] = {0};
                id.address().toString(buf);
                return [NSString stringWithUTF8String:buf];
            }
        }
    }

    return @"--------";
}

- (BOOL)isNodeOnline { return s_nodeOnline; }
- (BOOL)isNodeRunning { return s_nodeRunning; }

- (NSArray<NSString *> *)logEntries {
    std::lock_guard<std::mutex> lock(s_logMutex);
    return [s_logEntries copy];
}

- (NSString *)peerInfo {
    if (!s_node) return @"Node not started";
    ZT_PeerList *pl = ZT_Node_peers(s_node);
    if (!pl || pl->peerCount == 0) return @"No peers found";

    NSMutableString *result = [NSMutableString new];
    for (unsigned int i = 0; i < pl->peerCount; i++) {
        ZT_Peer *p = &pl->peers[i];
        char pAddr[11] = {0};
        ZeroTier::Address(p->address).toString(pAddr);
        [result appendFormat:@"%s latency=%dms paths=%u ver=%u.%u.%u\n",
         pAddr, p->latency, p->pathCount,
         p->versionMajor, p->versionMinor, p->versionRev];
    }
    ZT_Node_freeQueryResult(s_node, pl);
    return result;
}

- (NSString *)nodeStatusInfo {
    if (!s_node) return @"Node not started";

    ZT_NodeStatus status;
    memset(&status, 0, sizeof(status));
    ZT_Node_status(s_node, &status);

    char addrBuf[11] = {0};
    ZeroTier::Address(status.address).toString(addrBuf);

    return [NSString stringWithFormat:@"Address: %s\nOnline: %s\nTX: %lld  RX: %lld  TXFail: %lld",
            addrBuf,
            status.online ? "YES" : "NO",
            s_lastSendCount.load(),
            s_lastRecvCount.load(),
            s_lastSendFailCount.load()];
}

- (BOOL)startNode {
    if (s_nodeRunning) {
        ztLog(@"Node already running");
        return YES;
    }

    ztLog(@"Starting ZeroTier node (NWConnection mode)...");

    nw_parameters_t listenerParams = nw_parameters_create_secure_udp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );
    nw_parameters_set_reuse_local_address(listenerParams, true);

    s_listener4 = nw_listener_create(listenerParams);
    if (s_listener4) {
        nw_listener_set_queue(s_listener4, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        nw_listener_set_new_connection_handler(s_listener4, ^(nw_connection_t conn) {
            ztLog(@"NW: incoming IPv4 connection");
            nw_connection_set_queue(conn, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
            nw_connection_start(conn);
            receiveFromListener(conn);
        });
        nw_listener_set_state_changed_handler(s_listener4, ^(nw_listener_state_t state, nw_error_t error) {
            switch (state) {
                case nw_listener_state_ready:
                    s_localPort4 = (int)nw_listener_get_port(s_listener4);
                    ztLog([NSString stringWithFormat:@"NW IPv4 listener ready on port %d", s_localPort4]);
                    break;
                case nw_listener_state_failed:
                    ztLog([NSString stringWithFormat:@"NW IPv4 listener failed: %d", error ? (int)nw_error_get_error_code(error) : -1]);
                    break;
                case nw_listener_state_cancelled:
                    ztLog(@"NW IPv4 listener cancelled");
                    break;
                default:
                    break;
            }
        });
        nw_listener_start(s_listener4);
        ztLog(@"NW: IPv4 listener started");
    } else {
        ztLog(@"NW: failed to create IPv4 listener");
    }

    nw_parameters_t listenerParams6 = nw_parameters_create_secure_udp(
        NW_PARAMETERS_DISABLE_PROTOCOL,
        NW_PARAMETERS_DEFAULT_CONFIGURATION
    );
    nw_parameters_set_reuse_local_address(listenerParams6, true);

    s_listener6 = nw_listener_create(listenerParams6);
    if (s_listener6) {
        nw_listener_set_queue(s_listener6, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        nw_listener_set_new_connection_handler(s_listener6, ^(nw_connection_t conn) {
            ztLog(@"NW: incoming IPv6 connection");
            nw_connection_set_queue(conn, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
            nw_connection_start(conn);
            receiveFromListener(conn);
        });
        nw_listener_set_state_changed_handler(s_listener6, ^(nw_listener_state_t state, nw_error_t error) {
            switch (state) {
                case nw_listener_state_ready:
                    s_localPort6 = (int)nw_listener_get_port(s_listener6);
                    ztLog([NSString stringWithFormat:@"NW IPv6 listener ready on port %d", s_localPort6]);
                    break;
                case nw_listener_state_failed:
                    ztLog([NSString stringWithFormat:@"NW IPv6 listener failed: %d", error ? (int)nw_error_get_error_code(error) : -1]);
                    break;
                case nw_listener_state_cancelled:
                    ztLog(@"NW IPv6 listener cancelled");
                    break;
                default:
                    break;
            }
        });
        nw_listener_start(s_listener6);
        ztLog(@"NW: IPv6 listener started");
    } else {
        ztLog(@"NW: failed to create IPv6 listener");
    }

    int waitCount = 0;
    while ((s_localPort4 == 0 && s_localPort6 == 0) && waitCount < 30) {
        [NSThread sleepForTimeInterval:0.1];
        waitCount++;
    }
    ztLog([NSString stringWithFormat:@"NW: ports ready - IPv4=%d IPv6=%d", s_localPort4, s_localPort6]);

    if (s_localPort4 == 0 && s_localPort6 == 0) {
        ztLog(@"FATAL: No NW listeners available! Cannot start node.");
        return NO;
    }

    struct ZT_Node_Callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.version = 0;
    callbacks.statePutFunction = statePutFunction;
    callbacks.stateGetFunction = stateGetFunction;
    callbacks.wirePacketSendFunction = wirePacketSendFunction;
    callbacks.virtualNetworkFrameFunction = virtualNetworkFrameFunction;
    callbacks.virtualNetworkConfigFunction = virtualNetworkConfigFunction;
    callbacks.eventCallback = eventCallback;

    struct ZT_Node_Config config;
    memset(&config, 0, sizeof(config));
    config.enableEncryptedHello = 0;
    config.lowBandwidthMode = 0;

    int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);

    ztLog(@"Calling ZT_Node_new...");
    enum ZT_ResultCode rc = ZT_Node_new(&s_node, &config, nullptr, nullptr, &callbacks, now);
    if (rc != ZT_RESULT_OK) {
        ztLog([NSString stringWithFormat:@"ZT_Node_new FAILED with code: %d", (int)rc]);
        s_node = nullptr;
        return NO;
    }

    uint64_t addr = ZT_Node_address(s_node);
    char addrBuf[11] = {0};
    ZeroTier::Address(addr).toString(addrBuf);
    ztLog([NSString stringWithFormat:@"Node created successfully! Address: %s (0x%llx)", addrBuf, (unsigned long long)addr]);

    NSString *planetPath = [s_dataPath stringByAppendingPathComponent:@"planet"];
    NSData *planetData = [NSData dataWithContentsOfFile:planetPath];
    if (planetData) {
        ztLog([NSString stringWithFormat:@"Planet file saved: %lu bytes", (unsigned long)planetData.length]);
    } else {
        ztLog(@"WARNING: Planet file not saved after node creation!");
    }

    s_lastSendCount = 0;
    s_lastRecvCount = 0;
    s_lastSendFailCount = 0;

    s_nodeRunning = true;
    s_nodeThread = new std::thread(nodeThreadFunc);
    s_nodeThread->detach();

    ztLog(@"Node thread launched (NWConnection mode)");
    return YES;
}

- (void)stopNode {
    ztLog(@"Stopping node...");
    s_nodeRunning = false;
    if (s_nodeThread) {
        delete s_nodeThread;
        s_nodeThread = nullptr;
    }
    {
        std::lock_guard<std::mutex> lock(s_nodeMutex);
        if (s_node) {
            ZT_Node_delete(s_node);
            s_node = nullptr;
        }
    }
    {
        std::lock_guard<std::mutex> lock(s_connMutex);
        for (auto &pair : s_connections) {
            nw_connection_cancel(pair.second);
        }
        s_connections.clear();
    }
    if (s_listener4) { nw_listener_cancel(s_listener4); s_listener4 = nil; }
    if (s_listener6) { nw_listener_cancel(s_listener6); s_listener6 = nil; }
    s_localPort4 = 0;
    s_localPort6 = 0;
    s_nodeOnline = false;
    ztLog(@"Node stopped");
}

- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion {
    if (!s_nodeRunning) {
        ztLog(@"Node not running, starting before join...");
        if (![self startNode]) {
            ztLog(@"Failed to start node for join");
            if (completion) completion(NO);
            return;
        }
    }

    uint64_t nwid = [self parseNetworkId:networkId];
    if (nwid == 0) {
        ztLog([NSString stringWithFormat:@"Invalid network ID: '%@'", networkId]);
        if (completion) completion(NO);
        return;
    }

    self.currentNetworkId = networkId;
    ztLog([NSString stringWithFormat:@"Joining network %.16llx (input: %@)...", nwid, networkId]);

    {
        std::lock_guard<std::mutex> lock(s_nodeMutex);
        if (s_node) {
            enum ZT_ResultCode rc = ZT_Node_join(s_node, nwid, nullptr, nullptr);
            ztLog([NSString stringWithFormat:@"ZT_Node_join result: %d (0=OK, 1=IGNORED)", (int)rc]);
            if (rc != ZT_RESULT_OK && rc != ZT_RESULT_OK_IGNORED) {
                if (completion) completion(NO);
                return;
            }
        } else {
            ztLog(@"Node is null, cannot join");
            if (completion) completion(NO);
            return;
        }
    }

    [self saveNetwork:networkId];
    if (completion) completion(YES);
}

- (void)leaveNetwork {
    if (self.currentNetworkId.length > 0 && s_node) {
        uint64_t nwid = [self parseNetworkId:self.currentNetworkId];
        if (nwid != 0) {
            ztLog([NSString stringWithFormat:@"Leaving network %.16llx", nwid]);
            std::lock_guard<std::mutex> lock(s_nodeMutex);
            ZT_Node_leave(s_node, nwid, nullptr, nullptr);
        }
    }
    self.connected = NO;
    [self removeNetwork:self.currentNetworkId];
    self.currentNetworkId = nil;
}

- (NSArray<NSString *> *)savedNetworks {
    NSArray *networks = [[NSUserDefaults standardUserDefaults] objectForKey:@"zt_saved_networks"];
    return networks ?: @[];
}

- (NSString *)fullIdentityString {
    NSString *path = [s_dataPath stringByAppendingPathComponent:@"identity.secret"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return nil;
}

- (NSString *)publicIdentityString {
    NSString *path = [s_dataPath stringByAppendingPathComponent:@"identity.public"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return nil;
}

- (uint64_t)parseNetworkId:(NSString *)networkId {
    if (!networkId || networkId.length == 0) return 0;
    uint64_t nwid = 0;
    const char *cStr = [networkId UTF8String];
    for (int i = 0; cStr[i]; ++i) {
        if ((cStr[i] >= '0') && (cStr[i] <= '9'))
            nwid = (nwid << 4) | (uint64_t)(cStr[i] - '0');
        else if ((cStr[i] >= 'a') && (cStr[i] <= 'f'))
            nwid = (nwid << 4) | (uint64_t)(cStr[i] - 'a' + 10);
        else if ((cStr[i] >= 'A') && (cStr[i] <= 'F'))
            nwid = (nwid << 4) | (uint64_t)(cStr[i] - 'A' + 10);
    }
    return nwid;
}

- (void)saveNetwork:(NSString *)networkId {
    NSMutableArray *networks = [[[NSUserDefaults standardUserDefaults] objectForKey:@"zt_saved_networks"] mutableCopy] ?: [NSMutableArray new];
    if (![networks containsObject:networkId]) {
        [networks addObject:networkId];
        [[NSUserDefaults standardUserDefaults] setObject:networks forKey:@"zt_saved_networks"];
    }
}

- (void)removeNetwork:(NSString *)networkId {
    NSMutableArray *networks = [[[NSUserDefaults standardUserDefaults] objectForKey:@"zt_saved_networks"] mutableCopy] ?: [NSMutableArray new];
    [networks removeObject:networkId];
    [[NSUserDefaults standardUserDefaults] setObject:networks forKey:@"zt_saved_networks"];
}

- (void)dealloc {
    [self stopNode];
    s_sharedBridge = nil;
}

@end
