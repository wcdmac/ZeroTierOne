#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZeroTierBridge : NSObject

@property (nonatomic, assign) BOOL connected;
@property (nonatomic, copy, nullable) NSString *currentNetworkId;
@property (nonatomic, copy, nullable) void (^onStatusChange)(BOOL connected);
@property (nonatomic, copy, nullable) void (^onOnlineStatusChange)(BOOL online);

- (NSString *)nodeId;
- (BOOL)isNodeOnline;
- (BOOL)startNode;
- (void)stopNode;
- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion;
- (void)leaveNetwork;
- (NSArray<NSString *> *)savedNetworks;
- (NSString *)fullIdentityString;
- (NSString *)publicIdentityString;

@end

NS_ASSUME_NONNULL_END
