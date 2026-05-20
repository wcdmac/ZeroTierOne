#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZT-Tunnel] ========== Extension main() started ==========");
        NSLog(@"[ZT-Tunnel] PID: %d", getpid());
        NSLog(@"[ZT-Tunnel] argc: %d", argc);

        if ([NEProvider respondsToSelector:@selector(main)]) {
            NSLog(@"[ZT-Tunnel] Calling [NEProvider main]...");
            [NEProvider main];
            NSLog(@"[ZT-Tunnel] [NEProvider main] returned");
        } else {
            NSLog(@"[ZT-Tunnel] WARNING: NEProvider does not respond to +main selector!");
            [[NSRunLoop currentRunLoop] run];
        }
    }
    return 0;
}
