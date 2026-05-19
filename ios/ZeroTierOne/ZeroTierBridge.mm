#import "ZeroTierBridge.h"
#include <string>
#include <node/Identity.hpp>
#include <node/Utils.hpp>
#include <node/OSUtils.hpp>

@interface ZeroTierBridge ()
@end

@implementation ZeroTierBridge

- (NSString *)nodeId {
    NSString *identityPath = [self identityFilePath];
    ZeroTier::Identity id;

    if ([[NSFileManager defaultManager] fileExistsAtPath:identityPath]) {
        NSString *identityStr = [NSString stringWithContentsOfFile:identityPath encoding:NSUTF8StringEncoding error:nil];
        if (identityStr.length > 0) {
            std::string idStr([identityStr UTF8String]);
            if (id.fromString(idStr.c_str())) {
                char buf[11] = {0};
                id.address().toString(buf);
                return [NSString stringWithUTF8String:buf];
            }
        }
    }

    id.generate();
    char buf[11] = {0};
    id.address().toString(buf);
    NSString *addrStr = [NSString stringWithUTF8String:buf];

    char idBuf[ZT_IDENTITY_STRING_BUFFER_LENGTH] = {0};
    id.toString(true, idBuf);
    NSString *fullIdentity = [NSString stringWithUTF8String:idBuf];
    [fullIdentity writeToFile:identityPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    return addrStr;
}

- (BOOL)connected {
    return _connected;
}

- (void)joinNetwork:(NSString *)networkId completion:(void (^)(BOOL success))completion {
    if (networkId.length == 0) {
        if (completion) completion(NO);
        return;
    }

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

    if (nwid == 0) {
        if (completion) completion(NO);
        return;
    }

    self.connected = YES;
    self.currentNetworkId = networkId;

    [self saveNetwork:networkId];

    if (completion) completion(YES);
}

- (void)leaveNetwork {
    self.connected = NO;
    [self removeNetwork:self.currentNetworkId];
    self.currentNetworkId = nil;
}

- (NSArray<NSString *> *)savedNetworks {
    NSArray *networks = [[NSUserDefaults standardUserDefaults] objectForKey:@"zt_saved_networks"];
    return networks ?: @[];
}

- (NSString *)identityFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject;
    return [docs stringByAppendingPathComponent:@"identity.secret"];
}

- (NSString *)fullIdentityString {
    NSString *identityPath = [self identityFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:identityPath]) {
        return [NSString stringWithContentsOfFile:identityPath encoding:NSUTF8StringEncoding error:nil];
    }

    ZeroTier::Identity id;
    id.generate();
    char idBuf[ZT_IDENTITY_STRING_BUFFER_LENGTH] = {0};
    id.toString(true, idBuf);
    NSString *fullIdentity = [NSString stringWithUTF8String:idBuf];
    [fullIdentity writeToFile:identityPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    char buf[11] = {0};
    id.address().toString(buf);
    return fullIdentity;
}

- (NSString *)publicIdentityString {
    NSString *identityPath = [self identityFilePath];
    ZeroTier::Identity id;

    if ([[NSFileManager defaultManager] fileExistsAtPath:identityPath]) {
        NSString *identityStr = [NSString stringWithContentsOfFile:identityPath encoding:NSUTF8StringEncoding error:nil];
        if (identityStr.length > 0) {
            std::string idStr([identityStr UTF8String]);
            if (id.fromString(idStr.c_str())) {
                char idBuf[ZT_IDENTITY_STRING_BUFFER_LENGTH] = {0};
                id.toString(false, idBuf);
                return [NSString stringWithUTF8String:idBuf];
            }
        }
    }

    id.generate();
    char idBuf[ZT_IDENTITY_STRING_BUFFER_LENGTH] = {0};
    id.toString(false, idBuf);
    return [NSString stringWithUTF8String:idBuf];
}

#pragma mark - Private

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

@end
