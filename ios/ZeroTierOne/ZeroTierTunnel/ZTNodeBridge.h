#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZTNodeBridge : NSObject

@property (nonatomic, copy, nullable) void (^onFrameReceived)(NSData *frameData, unsigned int etherType);
@property (nonatomic, copy, nullable) void (^onNetworkConfigChanged)(NSDictionary *config);
@property (nonatomic, copy, nullable) void (^onStatusChanged)(BOOL online);

- (instancetype)initWithDataPath:(NSString *)dataPath;
- (NSString *)nodeId;
- (BOOL)isNodeOnline;
- (BOOL)isNodeRunning;
- (BOOL)isConnected;
- (uint64_t)macAddress;
- (NSString *)currentNetworkId;
- (BOOL)startNode;
- (void)stopNode;
- (void)joinNetwork:(NSString *)networkId;
- (void)leaveNetwork;
- (void)sendFrame:(NSData *)frameData etherType:(unsigned int)etherType;
- (NSString *)peerInfo;
- (NSString *)nodeStatusInfo;
- (NSString *)fullIdentityString;
- (NSString *)publicIdentityString;
- (uint64_t)parseNetworkId:(NSString *)networkId;

@end

NS_ASSUME_NONNULL_END
