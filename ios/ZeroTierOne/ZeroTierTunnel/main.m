#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <dlfcn.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZT-Tunnel] ========== Extension main() started ==========");
        NSLog(@"[ZT-Tunnel] PID: %d", getpid());

        Class neProviderClass = [NEProvider class];
        SEL mainSel = NSSelectorFromString(@"main");
        if ([neProviderClass respondsToSelector:mainSel]) {
            NSLog(@"[ZT-Tunnel] NEProvider responds to +main, calling via NSInvocation...");
            NSMethodSignature *sig = [neProviderClass methodSignatureForSelector:mainSel];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setSelector:mainSel];
            [invocation setTarget:neProviderClass];
            [invocation invoke];
            NSLog(@"[ZT-Tunnel] [NEProvider main] returned");
        } else {
            NSLog(@"[ZT-Tunnel] NEProvider does NOT respond to +main, trying dlsym fallback...");
            typedef int (*NEProviderMainFunc)(int, char **);
            NEProviderMainFunc fn = (NEProviderMainFunc)dlsym(RTLD_DEFAULT, "NEProviderMain");
            if (fn) {
                NSLog(@"[ZT-Tunnel] NEProviderMain found via dlsym, calling...");
                return fn(argc, argv);
            }
            NSLog(@"[ZT-Tunnel] FATAL: No entry point found, running NSRunLoop fallback");
            [[NSRunLoop currentRunLoop] run];
        }
    }
    return 0;
}
