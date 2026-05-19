#import "ZeroTierBridge.h"
#import <ZeroTierOne.h>

@interface ZeroTierBridge ()
@end

@implementation ZeroTierBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _connected = NO;
    }
    return self;
}

- (NSString *)nodeId {
    return @"0000000000";
}

- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion {
    self.connected = YES;
    if (completion) {
        completion(YES);
    }
}

- (void)leaveNetwork {
    self.connected = NO;
}

@end
