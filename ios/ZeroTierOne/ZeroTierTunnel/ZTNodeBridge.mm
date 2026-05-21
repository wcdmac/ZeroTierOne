#import "ZTNodeBridge.h"
#include <string>
#include <mutex>
#include <thread>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <vector>
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

#include <sys/stat.h>
#include <dirent.h>

static ZTNodeBridge *s_sharedBridge = nil;
static std::mutex s_nodeMutex;
static ZT_Node *s_node = nullptr;
static std::atomic<bool> s_nodeRunning(false);
static std::atomic<bool> s_nodeOnline(false);
static std::atomic<bool> s_connected(false);
static std::atomic<uint64_t> s_macAddress(0);
static std::atomic<uint64_t> s_currentNwid(0);
static std::thread *s_nodeThread = nullptr;
static volatile int64_t s_nextBackgroundTaskDeadline = 0;
static std::string s_dataPathStr;
static int s_udpSock4 = -1;
static int s_udpSock6 = -1;
static NSMutableArray<NSString *> *s_logEntries = nil;
static std::mutex s_logMutex;
static std::atomic<int64_t> s_lastSendCount(0);
static std::atomic<int64_t> s_lastRecvCount(0);
static std::atomic<int64_t> s_lastSendFailCount(0);

static void ztLog(const char *msg) {
    NSLog(@"[ZT-Tunnel] %s", msg);
    {
        std::lock_guard<std::mutex> lock(s_logMutex);
        if (!s_logEntries) s_logEntries = [NSMutableArray new];
        NSString *entry = [NSString stringWithFormat:@"%s", msg];
        [s_logEntries addObject:entry];
        if (s_logEntries.count > 500) [s_logEntries removeObjectAtIndex:0];
    }
    if (s_sharedBridge) {
        if (s_sharedBridge.onLogMessage) {
            s_sharedBridge.onLogMessage([NSString stringWithUTF8String:msg]);
        }
    }
}

static void ztLog(NSString *msg) {
    NSLog(@"[ZT-Tunnel] %@", msg);
    {
        std::lock_guard<std::mutex> lock(s_logMutex);
        if (!s_logEntries) s_logEntries = [NSMutableArray new];
        [s_logEntries addObject:msg];
        if (s_logEntries.count > 500) [s_logEntries removeObjectAtIndex:0];
    }
    if (s_sharedBridge) {
        if (s_sharedBridge.onLogMessage) {
            s_sharedBridge.onLogMessage(msg);
        }
    }
}

static void updateSharedStatus() {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.zerotier.ZeroTierOne"];
    if (defaults) {
        [defaults setBool:s_nodeOnline.load() forKey:@"isOnline"];
        [defaults setBool:s_connected.load() forKey:@"isConnected"];
        if (s_currentNwid.load() != 0) {
            char nwidBuf[17] = {0};
            snprintf(nwidBuf, sizeof(nwidBuf), "%.16llx", s_currentNwid.load());
            [defaults setObject:[NSString stringWithUTF8String:nwidBuf] forKey:@"currentNetworkId"];
        }
        [defaults synchronize];
    }
}

static void mkdirp(const char *path) {
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    mkdir(tmp, 0755);
}

static void statePutFunction(ZT_Node *node, void *uptr, void *tptr,
                              enum ZT_StateObjectType type, const uint64_t id[2],
                              const void *data, int len) {
    if (s_dataPathStr.empty()) return;

    const char *base = s_dataPathStr.c_str();
    char fullPath[2048];
    char parentDir[2048];

    switch (type) {
        case ZT_STATE_OBJECT_IDENTITY_SECRET:
            snprintf(fullPath, sizeof(fullPath), "%s/identity.secret", base);
            break;
        case ZT_STATE_OBJECT_IDENTITY_PUBLIC:
            snprintf(fullPath, sizeof(fullPath), "%s/identity.public", base);
            break;
        case ZT_STATE_OBJECT_PLANET:
            snprintf(fullPath, sizeof(fullPath), "%s/planet", base);
            break;
        case ZT_STATE_OBJECT_MOON:
            snprintf(fullPath, sizeof(fullPath), "%s/moons.d/%.16llx.moon", base, (unsigned long long)id[0]);
            break;
        case ZT_STATE_OBJECT_NETWORK_CONFIG:
            snprintf(fullPath, sizeof(fullPath), "%s/networks.d/%.16llx.conf", base, (unsigned long long)id[0]);
            break;
        case ZT_STATE_OBJECT_PEER:
            snprintf(fullPath, sizeof(fullPath), "%s/peers.d/%.16llx", base, (unsigned long long)id[0]);
            break;
        default:
            return;
    }

    if (len < 0) {
        unlink(fullPath);
        return;
    }

    if (!data || len <= 0) return;

    snprintf(parentDir, sizeof(parentDir), "%s", fullPath);
    char *lastSlash = strrchr(parentDir, '/');
    if (lastSlash) {
        *lastSlash = '\0';
        mkdirp(parentDir);
    }

    int fd = open(fullPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;

    ssize_t written = write(fd, data, (size_t)len);
    close(fd);

    if (written != (ssize_t)len) {
        unlink(fullPath);
    }
}

static int stateGetFunction(ZT_Node *node, void *uptr, void *tptr,
                             enum ZT_StateObjectType type, const uint64_t id[2],
                             void *data, unsigned int len) {
    if (s_dataPathStr.empty()) return -1;

    const char *base = s_dataPathStr.c_str();
    char fullPath[2048];

    switch (type) {
        case ZT_STATE_OBJECT_IDENTITY_SECRET:
            snprintf(fullPath, sizeof(fullPath), "%s/identity.secret", base);
            break;
        case ZT_STATE_OBJECT_IDENTITY_PUBLIC:
            snprintf(fullPath, sizeof(fullPath), "%s/identity.public", base);
            break;
        case ZT_STATE_OBJECT_PLANET:
            snprintf(fullPath, sizeof(fullPath), "%s/planet", base);
            break;
        case ZT_STATE_OBJECT_MOON:
            snprintf(fullPath, sizeof(fullPath), "%s/moons.d/%.16llx.moon", base, (unsigned long long)id[0]);
            break;
        case ZT_STATE_OBJECT_NETWORK_CONFIG:
            snprintf(fullPath, sizeof(fullPath), "%s/networks.d/%.16llx.conf", base, (unsigned long long)id[0]);
            break;
        case ZT_STATE_OBJECT_PEER:
            snprintf(fullPath, sizeof(fullPath), "%s/peers.d/%.16llx", base, (unsigned long long)id[0]);
            break;
        default:
            return -1;
    }

    int fd = open(fullPath, O_RDONLY);
    if (fd < 0) return -1;

    ssize_t n = read(fd, data, len);
    close(fd);

    if (n <= 0) return -1;
    return (int)n;
}

static int wirePacketSendFunction(ZT_Node *node, void *uptr, void *tptr,
                                   int64_t localSocket,
                                   const struct sockaddr_storage *remoteAddress,
                                   const void *packetData, unsigned int packetLength,
                                   unsigned int ttl) {
    ssize_t result = -1;
    char addrStr[INET6_ADDRSTRLEN] = {0};
    uint16_t port = 0;

    if (remoteAddress->ss_family == AF_INET && s_udpSock4 >= 0) {
        const struct sockaddr_in *sin = (const struct sockaddr_in *)remoteAddress;
        inet_ntop(AF_INET, &sin->sin_addr, addrStr, sizeof(addrStr));
        port = ntohs(sin->sin_port);
        result = sendto(s_udpSock4, packetData, packetLength, 0,
                        (const struct sockaddr *)remoteAddress, sizeof(struct sockaddr_in));
    } else if (remoteAddress->ss_family == AF_INET6 && s_udpSock6 >= 0) {
        const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)remoteAddress;
        inet_ntop(AF_INET6, &sin6->sin6_addr, addrStr, sizeof(addrStr));
        port = ntohs(sin6->sin6_port);
        result = sendto(s_udpSock6, packetData, packetLength, 0,
                        (const struct sockaddr *)remoteAddress, sizeof(struct sockaddr_in6));
    } else {
        char logBuf[128];
        snprintf(logBuf, sizeof(logBuf), "TX DROP: no socket for family %d", remoteAddress->ss_family);
        ztLog(logBuf);
        return -1;
    }

    if (result >= 0) {
        s_lastSendCount++;
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "TX %u bytes -> %s:%u", packetLength, addrStr, port);
        ztLog(logBuf);
    } else {
        s_lastSendFailCount++;
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "TX FAIL %u bytes -> %s:%u errno=%d (%s)", packetLength, addrStr, port, errno, strerror(errno));
        ztLog(logBuf);
    }
    return (result >= 0) ? 0 : -1;
}

static void virtualNetworkFrameFunction(ZT_Node *node, void *uptr, void *tptr,
                                         uint64_t nwid, void **nuptr,
                                         uint64_t sourceMac, uint64_t destMac,
                                         unsigned int etherType, unsigned int vlanId,
                                         const void *frameData, unsigned int frameLength) {
    if (s_sharedBridge && s_sharedBridge.onFrameReceived && frameData && frameLength > 0) {
        @autoreleasepool {
        NSData *nsData = [NSData dataWithBytes:frameData length:frameLength];
        s_sharedBridge.onFrameReceived(nsData, etherType);
        }
    }
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
    char logBuf[256];
    snprintf(logBuf, sizeof(logBuf), "NET CONFIG: nwid=%.16llx op=%s name=%s managed=%u", nwid, opStr, config->name, config->assignedAddressCount);
    ztLog(logBuf);

    s_currentNwid = nwid;
    s_macAddress = config->mac;

    if (op == ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_UP || op == ZT_VIRTUAL_NETWORK_CONFIG_OPERATION_CONFIG_UPDATE) {
        s_connected = true;
    } else {
        s_connected = false;
    }

    updateSharedStatus();

    if (s_sharedBridge && s_sharedBridge.onNetworkConfigChanged) {
        NSMutableDictionary *configDict = [NSMutableDictionary dictionary];
        char nwidBuf[17] = {0};
        snprintf(nwidBuf, sizeof(nwidBuf), "%.16llx", nwid);
        configDict[@"nwid"] = [NSString stringWithUTF8String:nwidBuf];
        configDict[@"op"] = [NSString stringWithUTF8String:opStr];
        configDict[@"mac"] = @(config->mac);
        configDict[@"mtu"] = @(config->mtu);
        configDict[@"name"] = [NSString stringWithUTF8String:config->name];

        NSMutableArray *ipv4Addrs = [NSMutableArray array];
        NSMutableArray *ipv6Addrs = [NSMutableArray array];
        NSMutableArray *routes = [NSMutableArray array];

        for (unsigned int i = 0; i < config->assignedAddressCount; i++) {
            char addrBuf[INET6_ADDRSTRLEN] = {0};
            if (config->assignedAddresses[i].ss_family == AF_INET) {
                const struct sockaddr_in *sin = (const struct sockaddr_in *)&config->assignedAddresses[i];
                inet_ntop(AF_INET, &sin->sin_addr, addrBuf, sizeof(addrBuf));
                [ipv4Addrs addObject:[NSString stringWithUTF8String:addrBuf]];
            } else if (config->assignedAddresses[i].ss_family == AF_INET6) {
                const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)&config->assignedAddresses[i];
                inet_ntop(AF_INET6, &sin6->sin6_addr, addrBuf, sizeof(addrBuf));
                [ipv6Addrs addObject:[NSString stringWithUTF8String:addrBuf]];
            }
        }
        configDict[@"ipv4Addresses"] = ipv4Addrs;
        configDict[@"ipv6Addresses"] = ipv6Addrs;

        for (unsigned int i = 0; i < config->routeCount; i++) {
            NSMutableDictionary *route = [NSMutableDictionary dictionary];
            char targetBuf[INET6_ADDRSTRLEN] = {0};
            char viaBuf[INET6_ADDRSTRLEN] = {0};
            if (config->routes[i].target.ss_family == AF_INET) {
                const struct sockaddr_in *sin = (const struct sockaddr_in *)&config->routes[i].target;
                inet_ntop(AF_INET, &sin->sin_addr, targetBuf, sizeof(targetBuf));
                route[@"target"] = [NSString stringWithUTF8String:targetBuf];
                if (config->routes[i].via.ss_family == AF_INET) {
                    const struct sockaddr_in *viaSin = (const struct sockaddr_in *)&config->routes[i].via;
                    inet_ntop(AF_INET, &viaSin->sin_addr, viaBuf, sizeof(viaBuf));
                    route[@"via"] = [NSString stringWithUTF8String:viaBuf];
                }
            } else if (config->routes[i].target.ss_family == AF_INET6) {
                const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)&config->routes[i].target;
                inet_ntop(AF_INET6, &sin6->sin6_addr, targetBuf, sizeof(targetBuf));
                route[@"target"] = [NSString stringWithUTF8String:targetBuf];
                if (config->routes[i].via.ss_family == AF_INET6) {
                    const struct sockaddr_in6 *viaSin6 = (const struct sockaddr_in6 *)&config->routes[i].via;
                    inet_ntop(AF_INET6, &viaSin6->sin6_addr, viaBuf, sizeof(viaBuf));
                    route[@"via"] = [NSString stringWithUTF8String:viaBuf];
                }
            }
            route[@"metric"] = @(config->routes[i].metric);
            [routes addObject:route];
        }
        configDict[@"routes"] = routes;

        s_sharedBridge.onNetworkConfigChanged(configDict);
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

    char logBuf[128];
    snprintf(logBuf, sizeof(logBuf), "EVENT: %s", eventName);
    ztLog(logBuf);

    switch (event) {
        case ZT_EVENT_ONLINE:
            s_nodeOnline = true;
            updateSharedStatus();
            if (s_sharedBridge && s_sharedBridge.onStatusChanged) {
                s_sharedBridge.onStatusChanged(YES);
            }
            break;
        case ZT_EVENT_OFFLINE:
            s_nodeOnline = false;
            updateSharedStatus();
            if (s_sharedBridge && s_sharedBridge.onStatusChanged) {
                s_sharedBridge.onStatusChanged(NO);
            }
            break;
        case ZT_EVENT_FATAL_ERROR_IDENTITY_COLLISION:
            ztLog("FATAL ERROR: Identity collision!");
            break;
        case ZT_EVENT_REMOTE_TRACE: {
            const ZT_RemoteTrace *rt = (const ZT_RemoteTrace *)metaData;
            if (rt) {
                char rtBuf[128];
                snprintf(rtBuf, sizeof(rtBuf), "REMOTE TRACE: from=%.10llx len=%u", rt->origin, rt->len);
                ztLog(rtBuf);
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
    char logBuf[128];
    snprintf(logBuf, sizeof(logBuf), "STATUS: addr=%s online=%d", addrBuf, status.online);
    ztLog(logBuf);

    ZT_PeerList *pl = ZT_Node_peers(s_node);
    if (pl) {
        snprintf(logBuf, sizeof(logBuf), "PEERS: %lu total", (unsigned long)pl->peerCount);
        ztLog(logBuf);
        for (unsigned int i = 0; i < pl->peerCount && i < 10; i++) {
            ZT_Peer *p = &pl->peers[i];
            char pAddr[11] = {0};
            ZeroTier::Address(p->address).toString(pAddr);
            snprintf(logBuf, sizeof(logBuf), "  PEER %s: latency=%d paths=%u ver=%u.%u.%u",
                   pAddr, p->latency, p->pathCount,
                   p->versionMajor, p->versionMinor, p->versionRev);
            ztLog(logBuf);
            for (unsigned int j = 0; j < p->pathCount && j < 4; j++) {
                char pathAddr[INET6_ADDRSTRLEN] = {0};
                if (p->paths[j].address.ss_family == AF_INET) {
                    const struct sockaddr_in *sin = (const struct sockaddr_in *)&p->paths[j].address;
                    inet_ntop(AF_INET, &sin->sin_addr, pathAddr, sizeof(pathAddr));
                    snprintf(logBuf, sizeof(logBuf), "    PATH: %s:%u pref=%d lastSend=%llu lastRecv=%llu",
                           pathAddr, ntohs(sin->sin_port), p->paths[j].preferred,
                           (unsigned long long)p->paths[j].lastSend, (unsigned long long)p->paths[j].lastReceive);
                    ztLog(logBuf);
                } else if (p->paths[j].address.ss_family == AF_INET6) {
                    const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)&p->paths[j].address;
                    inet_ntop(AF_INET6, &sin6->sin6_addr, pathAddr, sizeof(pathAddr));
                    snprintf(logBuf, sizeof(logBuf), "    PATH: [%s]:%u pref=%d lastSend=%llu lastRecv=%llu",
                           pathAddr, ntohs(sin6->sin6_port), p->paths[j].preferred,
                           (unsigned long long)p->paths[j].lastSend, (unsigned long long)p->paths[j].lastReceive);
                    ztLog(logBuf);
                }
            }
        }
        ZT_Node_freeQueryResult(s_node, pl);
    } else {
        ztLog("PEERS: none");
    }

    snprintf(logBuf, sizeof(logBuf), "STATS: sent=%lld recv=%lld sendFail=%lld",
           (long long)s_lastSendCount.load(), (long long)s_lastRecvCount.load(), (long long)s_lastSendFailCount.load());
    ztLog(logBuf);
}

static void nodeThreadFunc() {
    ztLog("Node thread started (BSD socket mode, NEPacketTunnel)");
    int64_t lastStatusLog = 0;
    int bgTaskCount = 0;

    while (s_nodeRunning) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        int64_t now = (int64_t)ts.tv_sec * 1000 + (int64_t)ts.tv_nsec / 1000000;

        {
            std::lock_guard<std::mutex> lock(s_nodeMutex);
            if (s_node) {
                enum ZT_ResultCode bgRc = ZT_Node_processBackgroundTasks(s_node, nullptr, now, &s_nextBackgroundTaskDeadline);
                bgTaskCount++;
                if (bgRc != ZT_RESULT_OK) {
                    char errBuf[64];
                    snprintf(errBuf, sizeof(errBuf), "processBackgroundTasks error: %d", (int)bgRc);
                    ztLog(errBuf);
                }
                if (bgTaskCount % 300 == 0) {
                    char bgBuf[64];
                    snprintf(bgBuf, sizeof(bgBuf), "BG task #%d running", bgTaskCount);
                    ztLog(bgBuf);
                }
            }
        }

        if (now - lastStatusLog >= 15000 && s_node) {
            lastStatusLog = now;
            logNodeStatus();
            updateSharedStatus();
        }

        uint8_t buf[ZT_MAX_PHYSMTU];
        struct sockaddr_storage fromAddr;
        socklen_t fromLen;

        struct timeval tv;
        int64_t sleepUntil = s_nextBackgroundTaskDeadline;
        int64_t sleepMs = (sleepUntil > 0 && sleepUntil > now) ? (sleepUntil - now) : 100;
        if (sleepMs > 500) sleepMs = 500;
        if (sleepMs < 10) sleepMs = 10;
        tv.tv_sec = (long)(sleepMs / 1000);
        tv.tv_usec = (long)((sleepMs % 1000) * 1000);

        fd_set readfds;
        FD_ZERO(&readfds);
        int maxFd = 0;
        if (s_udpSock4 >= 0) { FD_SET(s_udpSock4, &readfds); maxFd = (s_udpSock4 > maxFd) ? s_udpSock4 : maxFd; }
        if (s_udpSock6 >= 0) { FD_SET(s_udpSock6, &readfds); maxFd = (s_udpSock6 > maxFd) ? s_udpSock6 : maxFd; }

        if (maxFd > 0) {
            int selRc = select(maxFd + 1, &readfds, nullptr, nullptr, &tv);
            if (selRc < 0) {
                if (errno != EINTR) {
                    char errBuf[128];
                    snprintf(errBuf, sizeof(errBuf), "select() error: %d (%s)", errno, strerror(errno));
                    ztLog(errBuf);
                }
                continue;
            }

            if (s_udpSock4 >= 0 && FD_ISSET(s_udpSock4, &readfds)) {
                fromLen = sizeof(fromAddr);
                ssize_t n = recvfrom(s_udpSock4, buf, sizeof(buf), 0, (struct sockaddr *)&fromAddr, &fromLen);
                if (n > 0) {
                    s_lastRecvCount++;
                    char rAddr[INET6_ADDRSTRLEN] = {0};
                    uint16_t rPort = 0;
                    if (fromAddr.ss_family == AF_INET) {
                        const struct sockaddr_in *sin = (const struct sockaddr_in *)&fromAddr;
                        inet_ntop(AF_INET, &sin->sin_addr, rAddr, sizeof(rAddr));
                        rPort = ntohs(sin->sin_port);
                    }
                    char rxBuf[128];
                    snprintf(rxBuf, sizeof(rxBuf), "RX4 %zd bytes from %s:%u", n, rAddr, rPort);
                    ztLog(rxBuf);
                    std::lock_guard<std::mutex> lock(s_nodeMutex);
                    if (s_node) {
                        ZT_Node_processWirePacket(s_node, nullptr, now, s_udpSock4, &fromAddr, buf, (unsigned int)n, &s_nextBackgroundTaskDeadline);
                    }
                } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                    char errBuf[128];
                    snprintf(errBuf, sizeof(errBuf), "recvfrom IPv4 error: %d (%s)", errno, strerror(errno));
                    ztLog(errBuf);
                }
            }
            if (s_udpSock6 >= 0 && FD_ISSET(s_udpSock6, &readfds)) {
                fromLen = sizeof(fromAddr);
                ssize_t n = recvfrom(s_udpSock6, buf, sizeof(buf), 0, (struct sockaddr *)&fromAddr, &fromLen);
                if (n > 0) {
                    s_lastRecvCount++;
                    char rAddr[INET6_ADDRSTRLEN] = {0};
                    uint16_t rPort = 0;
                    if (fromAddr.ss_family == AF_INET6) {
                        const struct sockaddr_in6 *sin6 = (const struct sockaddr_in6 *)&fromAddr;
                        inet_ntop(AF_INET6, &sin6->sin6_addr, rAddr, sizeof(rAddr));
                        rPort = ntohs(sin6->sin6_port);
                    }
                    char rxBuf[128];
                    snprintf(rxBuf, sizeof(rxBuf), "RX6 %zd bytes from %s:%u", n, rAddr, rPort);
                    ztLog(rxBuf);
                    std::lock_guard<std::mutex> lock(s_nodeMutex);
                    if (s_node) {
                        ZT_Node_processWirePacket(s_node, nullptr, now, s_udpSock6, &fromAddr, buf, (unsigned int)n, &s_nextBackgroundTaskDeadline);
                    }
                } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                    char errBuf[128];
                    snprintf(errBuf, sizeof(errBuf), "recvfrom IPv6 error: %d (%s)", errno, strerror(errno));
                    ztLog(errBuf);
                }
            }
        } else {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
        }
    }

    ztLog("Node thread stopped");
}

@implementation ZTNodeBridge

- (instancetype)initWithDataPath:(NSString *)dataPath {
    self = [super init];
    if (self) {
        s_sharedBridge = self;
        s_logEntries = [NSMutableArray new];
        s_dataPathStr = std::string([dataPath UTF8String]);
        mkdir(s_dataPathStr.c_str(), 0755);

        ztLog([NSString stringWithFormat:@"Data path: %@", dataPath]);
        ztLog(@"NEPacketTunnel extension - BSD socket mode");

        struct stat st;
        char planetPath[2048];
        snprintf(planetPath, sizeof(planetPath), "%s/planet", s_dataPathStr.c_str());
        if (stat(planetPath, &st) == 0) {
            ztLog([NSString stringWithFormat:@"Planet file exists: %lld bytes", (long long)st.st_size]);
        } else {
            ztLog(@"No cached planet file (will use built-in defaults)");
        }

        char idSecPath[2048];
        snprintf(idSecPath, sizeof(idSecPath), "%s/identity.secret", s_dataPathStr.c_str());
        if (stat(idSecPath, &st) == 0) {
            ztLog([NSString stringWithFormat:@"Identity file exists: %lld bytes", (long long)st.st_size]);
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
            NSString *nodeId = [NSString stringWithUTF8String:buf];
            NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.zerotier.ZeroTierOne"];
            [defaults setObject:nodeId forKey:@"nodeId"];
            [defaults synchronize];
            return nodeId;
        }
    }

    char pubPathC[2048];
    snprintf(pubPathC, sizeof(pubPathC), "%s/identity.public", s_dataPathStr.c_str());
    NSString *pubPath = [NSString stringWithUTF8String:pubPathC];
    NSData *data = [NSData dataWithContentsOfFile:pubPath];
    if (data && data.length > 0) {
        NSString *pubStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (pubStr.length > 0) {
            ZeroTier::Identity id;
            if (id.fromString([pubStr UTF8String])) {
                char buf[11] = {0};
                id.address().toString(buf);
                NSString *nodeId = [NSString stringWithUTF8String:buf];
                NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.zerotier.ZeroTierOne"];
                [defaults setObject:nodeId forKey:@"nodeId"];
                [defaults synchronize];
                return nodeId;
            }
        }
    }

    return @"--------";
}

- (BOOL)isNodeOnline { return s_nodeOnline; }
- (BOOL)isNodeRunning { return s_nodeRunning; }
- (BOOL)isConnected { return s_connected; }
- (uint64_t)macAddress { return s_macAddress; }

- (NSString *)currentNetworkId {
    if (s_currentNwid.load() != 0) {
        char buf[17] = {0};
        snprintf(buf, sizeof(buf), "%.16llx", s_currentNwid.load());
        return [NSString stringWithUTF8String:buf];
    }
    return nil;
}

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

    return [NSString stringWithFormat:@"Address: %s\nOnline: %s\nConnected: %s\nTX: %lld  RX: %lld  TXFail: %lld",
            addrBuf,
            status.online ? "YES" : "NO",
            s_connected.load() ? "YES" : "NO",
            s_lastSendCount.load(),
            s_lastRecvCount.load(),
            s_lastSendFailCount.load()];
}

- (BOOL)startNode {
    if (s_nodeRunning) {
        ztLog(@"Node already running");
        return YES;
    }

    ztLog(@"Starting ZeroTier node (NEPacketTunnel, BSD socket mode)...");

    s_udpSock4 = socket(AF_INET, SOCK_DGRAM, 0);
    if (s_udpSock4 >= 0) {
        int flags = fcntl(s_udpSock4, F_GETFL, 0);
        fcntl(s_udpSock4, F_SETFL, flags | O_NONBLOCK);
        int val = 1;
        setsockopt(s_udpSock4, SOL_SOCKET, SO_REUSEADDR, &val, sizeof(val));

        struct sockaddr_in localAddr;
        memset(&localAddr, 0, sizeof(localAddr));
        localAddr.sin_family = AF_INET;
        localAddr.sin_addr.s_addr = INADDR_ANY;
        localAddr.sin_port = 0;
        if (bind(s_udpSock4, (struct sockaddr *)&localAddr, sizeof(localAddr)) < 0) {
            ztLog([NSString stringWithFormat:@"IPv4 bind failed: %s (errno=%d)", strerror(errno), errno]);
            close(s_udpSock4);
            s_udpSock4 = -1;
        } else {
            struct sockaddr_in boundAddr;
            socklen_t addrLen = sizeof(boundAddr);
            getsockname(s_udpSock4, (struct sockaddr *)&boundAddr, &addrLen);
            ztLog([NSString stringWithFormat:@"IPv4 UDP bound on port %d (fd=%d)", ntohs(boundAddr.sin_port), s_udpSock4]);
        }
    } else {
        ztLog([NSString stringWithFormat:@"IPv4 socket() failed: %s (errno=%d)", strerror(errno), errno]);
    }

    s_udpSock6 = socket(AF_INET6, SOCK_DGRAM, 0);
    if (s_udpSock6 >= 0) {
        int flags = fcntl(s_udpSock6, F_GETFL, 0);
        fcntl(s_udpSock6, F_SETFL, flags | O_NONBLOCK);
        int v6only = 1;
        setsockopt(s_udpSock6, IPPROTO_IPV6, IPV6_V6ONLY, &v6only, sizeof(v6only));
        int val = 1;
        setsockopt(s_udpSock6, SOL_SOCKET, SO_REUSEADDR, &val, sizeof(val));

        struct sockaddr_in6 localAddr6;
        memset(&localAddr6, 0, sizeof(localAddr6));
        localAddr6.sin6_family = AF_INET6;
        localAddr6.sin6_addr = in6addr_any;
        localAddr6.sin6_port = 0;
        if (bind(s_udpSock6, (struct sockaddr *)&localAddr6, sizeof(localAddr6)) < 0) {
            ztLog([NSString stringWithFormat:@"IPv6 bind failed: %s (errno=%d)", strerror(errno), errno]);
            close(s_udpSock6);
            s_udpSock6 = -1;
        } else {
            struct sockaddr_in6 boundAddr6;
            socklen_t addrLen6 = sizeof(boundAddr6);
            getsockname(s_udpSock6, (struct sockaddr *)&boundAddr6, &addrLen6);
            ztLog([NSString stringWithFormat:@"IPv6 UDP bound on port %d (fd=%d)", ntohs(boundAddr6.sin6_port), s_udpSock6]);
        }
    } else {
        ztLog([NSString stringWithFormat:@"IPv6 socket() failed: %s (errno=%d)", strerror(errno), errno]);
    }

    if (s_udpSock4 < 0 && s_udpSock6 < 0) {
        ztLog(@"FATAL: No UDP sockets available! Cannot start node.");
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

    [self nodeId];

    s_lastSendCount = 0;
    s_lastRecvCount = 0;
    s_lastSendFailCount = 0;

    s_nodeRunning = true;
    s_nodeThread = new std::thread(nodeThreadFunc);
    s_nodeThread->detach();

    ztLog(@"Node thread launched (NEPacketTunnel mode)");
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
    if (s_udpSock4 >= 0) { close(s_udpSock4); s_udpSock4 = -1; }
    if (s_udpSock6 >= 0) { close(s_udpSock6); s_udpSock6 = -1; }
    s_nodeOnline = false;
    s_connected = false;
    updateSharedStatus();
    ztLog(@"Node stopped");
}

- (void)joinNetwork:(NSString *)networkId {
    if (!s_nodeRunning) {
        ztLog(@"Node not running, cannot join network");
        return;
    }

    uint64_t nwid = [self parseNetworkId:networkId];
    if (nwid == 0) {
        ztLog([NSString stringWithFormat:@"Invalid network ID: '%@'", networkId]);
        return;
    }

    ztLog([NSString stringWithFormat:@"Joining network %.16llx (input: %@)...", nwid, networkId]);

    {
        std::lock_guard<std::mutex> lock(s_nodeMutex);
        if (s_node) {
            enum ZT_ResultCode rc = ZT_Node_join(s_node, nwid, nullptr, nullptr);
            ztLog([NSString stringWithFormat:@"ZT_Node_join result: %d (0=OK, 1=IGNORED)", (int)rc]);
        } else {
            ztLog(@"Node is null, cannot join");
        }
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.zerotier.ZeroTierOne"];
    NSMutableArray *networks = [[defaults stringArrayForKey:@"savedNetworks"] mutableCopy] ?: [NSMutableArray array];
    if (![networks containsObject:networkId]) {
        [networks addObject:networkId];
        [defaults setObject:networks forKey:@"savedNetworks"];
    }
    [defaults synchronize];
}

- (void)leaveNetwork {
    if (s_currentNwid.load() != 0 && s_node) {
        ztLog([NSString stringWithFormat:@"Leaving network %.16llx", s_currentNwid.load()]);
        std::lock_guard<std::mutex> lock(s_nodeMutex);
        ZT_Node_leave(s_node, s_currentNwid.load(), nullptr, nullptr);
    }
    s_connected = false;
    s_currentNwid = 0;
    updateSharedStatus();
}

- (void)sendFrame:(NSData *)frameData etherType:(unsigned int)etherType {
    if (!s_node || !s_nodeRunning || s_currentNwid.load() == 0) return;

    uint64_t nwid = s_currentNwid.load();
    uint64_t mac = s_macAddress.load();
    int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);

    std::lock_guard<std::mutex> lock(s_nodeMutex);
    ZT_Node_processVirtualNetworkFrame(s_node, nullptr, now, nwid, mac, 0xffffffffffffULL,
                                        etherType, 0,
                                        frameData.bytes, (unsigned int)frameData.length,
                                        &s_nextBackgroundTaskDeadline);
}

- (NSString *)fullIdentityString {
    char pathC[2048];
    snprintf(pathC, sizeof(pathC), "%s/identity.secret", s_dataPathStr.c_str());
    int fd = open(pathC, O_RDONLY);
    if (fd < 0) return nil;
    off_t fileSize = lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);
    if (fileSize <= 0 || fileSize > 65536) { close(fd); return nil; }
    std::vector<char> buf(fileSize + 1, 0);
    ssize_t n = read(fd, buf.data(), fileSize);
    close(fd);
    if (n <= 0) return nil;
    return [NSString stringWithUTF8String:buf.data()];
}

- (NSString *)publicIdentityString {
    char pathC[2048];
    snprintf(pathC, sizeof(pathC), "%s/identity.public", s_dataPathStr.c_str());
    int fd = open(pathC, O_RDONLY);
    if (fd < 0) return nil;
    off_t fileSize = lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);
    if (fileSize <= 0 || fileSize > 65536) { close(fd); return nil; }
    std::vector<char> buf(fileSize + 1, 0);
    ssize_t n = read(fd, buf.data(), fileSize);
    close(fd);
    if (n <= 0) return nil;
    return [NSString stringWithUTF8String:buf.data()];
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

- (void)dealloc {
    [self stopNode];
    s_sharedBridge = nil;
}

@end
