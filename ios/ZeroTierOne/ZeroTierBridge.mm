#import "ZeroTierBridge.h"
#import <ZeroTierOne.h>

@interface ZeroTierBridge ()
@property (nonatomic, assign) void *node;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, copy) NSString *currentNetworkId;
@end

static int _nodeCallback(void *msg, void *arg) {
    return 0;
}

@implementation ZeroTierBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _connected = NO;
        _node = NULL;
        _currentNetworkId = nil;
    }
    return self;
}

- (NSString *)getNodeId {
    return @"0000000000";
}

- (BOOL)isConnected {
    return _connected;
}

- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion {
    self.currentNetworkId = networkId;
    self.connected = YES;
    if (completion) {
        completion(YES);
    }
}

- (void)leaveNetwork {
    self.currentNetworkId = nil;
    self.connected = NO;
}

@end
