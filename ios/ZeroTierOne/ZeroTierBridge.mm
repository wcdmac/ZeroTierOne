#import "ZeroTierBridge.h"
#include <string>
#include <map>
#include <mutex>
#include <thread>
#include <atomic>
#include <cstring>
#include <cstdlib>

#include <ZeroTierOne.h>
#include <node/Identity.hpp>
#include <node/Utils.hpp>

static ZeroTierBridge *s_sharedBridge = nil;
static std::mutex s_nodeMutex;
static ZT_Node *s_node = nullptr;
static std::atomic<bool> s_nodeRunning(false);
static std::atomic<bool> s_nodeOnline(false);
static std::thread *s_nodeThread = nullptr;
static volatile int64_t s_nextBackgroundTaskDeadline = 0;

static NSString *s_dataPath = nil;
static int s_udpSock = -1;
static int s_udpSock6 = -1;

static void statePutFunction(ZT_Node *node, void *uptr, void *tptr,
                              enum ZT_StateObjectType type, const uint64_t id[2],
                              const void *data, int len) {
    NSString *dir = s_dataPath;
    if (!dir) return;

    NSString *filename = nil;
    switch (type) {
        case ZT_STATE_OBJECT_IDENTITY_SECRET:
            filename = @"identity.secret";
            break;
        case ZT_STATE_OBJECT_IDENTITY_PUBLIC:
            filename = @"identity.public";
            break;
        case ZT_STATE_OBJECT_PLANET:
            filename = @"planet";
            break;
        case ZT_STATE_OBJECT_MOON:
            filename = [NSString stringWithFormat:@"moons.d/%.16llx.moon", id[0]];
            break;
        case ZT_STATE_OBJECT_NETWORK_CONFIG:
            filename = [NSString stringWithFormat:@"networks.d/%.16llx.conf", id[0]];
            break;
        case ZT_STATE_OBJECT_PEER:
            filename = [NSString stringWithFormat:@"peers.d/%.16llx", id[0]];
            break;
        default:
            return;
    }

    NSString *fullPath = [dir stringByAppendingPathComponent:filename];
    NSString *parentDir = [fullPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];

    if (len < 0) {
        [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
    } else if (data && len > 0) {
        NSData *nsData = [NSData dataWithBytes:data length:(NSUInteger)len];
        [nsData writeToFile:fullPath atomically:YES];
    }
}

static int stateGetFunction(ZT_Node *node, void *uptr, void *tptr,
                             enum ZT_StateObjectType type, const uint64_t id[2],
                             void *data, unsigned int len) {
    NSString *dir = s_dataPath;
    if (!dir) return -1;

    NSString *filename = nil;
    switch (type) {
        case ZT_STATE_OBJECT_IDENTITY_SECRET:
            filename = @"identity.secret";
            break;
        case ZT_STATE_OBJECT_IDENTITY_PUBLIC:
            filename = @"identity.public";
            break;
        case ZT_STATE_OBJECT_PLANET:
            filename = @"planet";
            break;
        case ZT_STATE_OBJECT_MOON:
            filename = [NSString stringWithFormat:@"moons.d/%.16llx.moon", id[0]];
            break;
        case ZT_STATE_OBJECT_NETWORK_CONFIG:
            filename = [NSString stringWithFormat:@"networks.d/%.16llx.conf", id[0]];
            break;
        case ZT_STATE_OBJECT_PEER:
            filename = [NSString stringWithFormat:@"peers.d/%.16llx", id[0]];
            break;
        default:
            return -1;
    }

    NSString *fullPath = [dir stringByAppendingPathComponent:filename];
    NSData *nsData = [NSData dataWithContentsOfFile:fullPath];
    if (!nsData || nsData.length == 0 || nsData.length > len) return -1;

    memcpy(data, nsData.bytes, nsData.length);
    return (int)nsData.length;
}

static int wirePacketSendFunction(ZT_Node *node, void *uptr, void *tptr,
                                   int64_t localSocket,
                                   const struct sockaddr_storage *remoteAddress,
                                   const void *packetData, unsigned int packetLength,
                                   unsigned int ttl) {
    ssize_t result = -1;
    if (remoteAddress->ss_family == AF_INET && s_udpSock >= 0) {
        result = sendto(s_udpSock, packetData, packetLength, 0,
                        (const struct sockaddr *)remoteAddress, sizeof(struct sockaddr_in));
    } else if (remoteAddress->ss_family == AF_INET6 && s_udpSock6 >= 0) {
        result = sendto(s_udpSock6, packetData, packetLength, 0,
                        (const struct sockaddr *)remoteAddress, sizeof(struct sockaddr_in6));
    }
    return (result >= 0) ? 0 : -1;
}

static void virtualNetworkFrameFunction(ZT_Node *node, void *uptr, void *tptr,
                                         uint64_t nwid, void **nuptr,
                                         uint64_t sourceMac, uint64_t destMac,
                                         unsigned int etherType, unsigned int vlanId,
                                         const void *frameData, unsigned int frameLength) {
}

static void virtualNetworkConfigFunction(ZT_Node *node, void *uptr, void *tptr,
                                          uint64_t nwid, void **nuptr,
                                          enum ZT_VirtualNetworkConfigOperation op,
                                          const ZT_VirtualNetworkConfig *config) {
    if (s_sharedBridge) {
        dispatch_async(dispatch_get_main_queue(), ^{
            s_sharedBridge.connected = (op != ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_DESTROY);
            if (s_sharedBridge.onStatusChange) {
                s_sharedBridge.onStatusChange(s_sharedBridge.connected);
            }
        });
    }
}

static void eventCallback(ZT_Node *node, void *uptr, void *tptr,
                           enum ZT_Event event, const void *metaData) {
    switch (event) {
        case ZT_EVENT_ONLINE:
            s_nodeOnline = true;
            if (s_sharedBridge) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s_sharedBridge.onOnlineStatusChange) {
                        s_sharedBridge.onOnlineStatusChange(YES);
                    }
                });
            }
            break;
        case ZT_EVENT_OFFLINE:
            s_nodeOnline = false;
            if (s_sharedBridge) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s_sharedBridge.onOnlineStatusChange) {
                        s_sharedBridge.onOnlineStatusChange(NO);
                    }
                });
            }
            break;
        default:
            break;
    }
}

static void nodeThreadFunc() {
    s_nextBackgroundTaskDeadline = 0;

    while (s_nodeRunning) {
        int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);

        {
            std::lock_guard<std::mutex> lock(s_nodeMutex);
            if (s_node) {
                ZT_Node_processBackgroundTasks(s_node, nullptr, now, &s_nextBackgroundTaskDeadline);
            }
        }

        uint8_t buf[ZT_MAX_PHYSMTU];
        struct sockaddr_storage fromAddr;
        socklen_t fromLen = sizeof(fromAddr);

        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 100000;
        fd_set readfds;
        FD_ZERO(&readfds);
        int maxFd = 0;
        if (s_udpSock >= 0) {
            FD_SET(s_udpSock, &readfds);
            maxFd = (s_udpSock > maxFd) ? s_udpSock : maxFd;
        }
        if (s_udpSock6 >= 0) {
            FD_SET(s_udpSock6, &readfds);
            maxFd = (s_udpSock6 > maxFd) ? s_udpSock6 : maxFd;
        }
        if (maxFd > 0) {
            select(maxFd + 1, &readfds, nullptr, nullptr, &tv);
            if (s_udpSock >= 0 && FD_ISSET(s_udpSock, &readfds)) {
                ssize_t n = recvfrom(s_udpSock, buf, sizeof(buf), 0,
                                     (struct sockaddr *)&fromAddr, &fromLen);
                if (n > 0) {
                    std::lock_guard<std::mutex> lock(s_nodeMutex);
                    if (s_node) {
                        ZT_Node_processWirePacket(s_node, nullptr, now, 0, &fromAddr, buf, (unsigned int)n, &s_nextBackgroundTaskDeadline);
                    }
                }
            }
            if (s_udpSock6 >= 0 && FD_ISSET(s_udpSock6, &readfds)) {
                ssize_t n = recvfrom(s_udpSock6, buf, sizeof(buf), 0,
                                     (struct sockaddr *)&fromAddr, &fromLen);
                if (n > 0) {
                    std::lock_guard<std::mutex> lock(s_nodeMutex);
                    if (s_node) {
                        ZT_Node_processWirePacket(s_node, nullptr, now, 0, &fromAddr, buf, (unsigned int)n, &s_nextBackgroundTaskDeadline);
                    }
                }
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }
}

@implementation ZeroTierBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _connected = NO;
        s_sharedBridge = self;

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        s_dataPath = paths.firstObject;
        NSString *ztDir = [s_dataPath stringByAppendingPathComponent:@"zerotier"];
        [[NSFileManager defaultManager] createDirectoryAtPath:ztDir withIntermediateDirectories:YES attributes:nil error:nil];
        s_dataPath = ztDir;
    }
    return self;
}

- (NSString *)nodeId {
    if (s_node) {
        char buf[11] = {0};
        ZeroTier::Address(s_node ? ZT_Node_address(s_node) : 0).toString(buf);
        return [NSString stringWithUTF8String:buf];
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

- (BOOL)isNodeOnline {
    return s_nodeOnline;
}

- (BOOL)startNode {
    if (s_nodeRunning) return YES;

    s_udpSock = socket(AF_INET, SOCK_DGRAM, 0);
    if (s_udpSock >= 0) {
        int flags = fcntl(s_udpSock, F_GETFL, 0);
        fcntl(s_udpSock, F_SETFL, flags | O_NONBLOCK);

        struct sockaddr_in localAddr;
        memset(&localAddr, 0, sizeof(localAddr));
        localAddr.sin_family = AF_INET;
        localAddr.sin_addr.s_addr = INADDR_ANY;
        localAddr.sin_port = 0;
        if (bind(s_udpSock, (struct sockaddr *)&localAddr, sizeof(localAddr)) < 0) {
            close(s_udpSock);
            s_udpSock = -1;
        }
    }

    s_udpSock6 = socket(AF_INET6, SOCK_DGRAM, 0);
    if (s_udpSock6 >= 0) {
        int flags = fcntl(s_udpSock6, F_GETFL, 0);
        fcntl(s_udpSock6, F_SETFL, flags | O_NONBLOCK);

        int v6only = 1;
        setsockopt(s_udpSock6, IPPROTO_IPV6, IPV6_V6ONLY, &v6only, sizeof(v6only));

        struct sockaddr_in6 localAddr6;
        memset(&localAddr6, 0, sizeof(localAddr6));
        localAddr6.sin6_family = AF_INET6;
        localAddr6.sin6_addr = in6addr_any;
        localAddr6.sin6_port = 0;
        if (bind(s_udpSock6, (struct sockaddr *)&localAddr6, sizeof(localAddr6)) < 0) {
            close(s_udpSock6);
            s_udpSock6 = -1;
        }
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

    enum ZT_ResultCode rc = ZT_Node_new(&s_node, &config, nullptr, nullptr, &callbacks, now);
    if (rc != ZT_RESULT_OK) {
        return NO;
    }

    s_nodeRunning = true;
    s_nodeThread = new std::thread(nodeThreadFunc);
    s_nodeThread->detach();

    return YES;
}

- (void)stopNode {
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

    if (s_udpSock >= 0) {
        close(s_udpSock);
        s_udpSock = -1;
    }
    if (s_udpSock6 >= 0) {
        close(s_udpSock6);
        s_udpSock6 = -1;
    }
    s_nodeOnline = false;
}

- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion {
    if (!s_nodeRunning) {
        [self startNode];
    }

    uint64_t nwid = [self parseNetworkId:networkId];
    if (nwid == 0) {
        if (completion) completion(NO);
        return;
    }

    self.currentNetworkId = networkId;

    {
        std::lock_guard<std::mutex> lock(s_nodeMutex);
        if (s_node) {
            enum ZT_ResultCode rc = ZT_Node_join(s_node, nwid, nullptr, nullptr);
            if (rc != ZT_RESULT_OK) {
                if (completion) completion(NO);
                return;
            }
        }
    }

    [self saveNetwork:networkId];

    if (completion) completion(YES);
}

- (void)leaveNetwork {
    if (self.currentNetworkId.length > 0 && s_node) {
        uint64_t nwid = [self parseNetworkId:self.currentNetworkId];
        if (nwid != 0) {
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
    if (data) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSString *)publicIdentityString {
    NSString *path = [s_dataPath stringByAppendingPathComponent:@"identity.public"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

#pragma mark - Private

- (uint64_t)parseNetworkId:(NSString *)networkId {
    if (!networkId || networkId.length == 0) return 0;
    uint64_t nwid = 0;
    const char *cStr = [networkId UTF8String];
    for (int i = 0; cStr[i]; ++i) {
        if ((cStr[i] >= '0') && (cStr[i] <= '9')) {
            nwid = (nwid << 4) | (uint64_t)(cStr[i] - '0');
        } else if ((cStr[i] >= 'a') && (cStr[i] <= 'f')) {
            nwid = (nwid << 4) | (uint64_t)(cStr[i] - 'a' + 10);
        } else if ((cStr[i] >= 'A') && (cStr[i] <= 'F')) {
            nwid = (nwid << 4) | (uint64_t)(cStr[i] - 'A' + 10);
        }
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
