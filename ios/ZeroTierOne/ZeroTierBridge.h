#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZeroTierBridge : NSObject

- (NSString *)getNodeId;
- (BOOL)isConnected;
- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion;
- (void)leaveNetwork;

@end

NS_ASSUME_NONNULL_END
