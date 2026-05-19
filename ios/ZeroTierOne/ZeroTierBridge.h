#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZeroTierBridge : NSObject

@property (nonatomic, readonly) NSString *nodeId;
@property (nonatomic, assign) BOOL connected;

- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion;
- (void)leaveNetwork;

@end

NS_ASSUME_NONNULL_END
