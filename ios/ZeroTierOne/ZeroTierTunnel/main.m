#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZT-Tunnel] ========== Extension main() started ==========");
        NSLog(@"[ZT-Tunnel] PID: %d", getpid());

        SEL mainSel = NSSelectorFromString(@"main");
        if ([NEProvider respondsToSelector:mainSel]) {
            NSLog(@"[ZT-Tunnel] NEProvider responds to +main, calling via performSelector...");
            NSMethodSignature *sig = [NEProvider methodSignatureForSelector:mainSel];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
            [invocation setSelector:mainSel];
            [invocation setTarget:NEProvider];
            [invocation invoke];
            NSLog(@"[ZT-Tunnel] [NEProvider main] returned");
        } else {
            NSLog(@"[ZT-Tunnel] WARNING: NEProvider does not respond to +main!");
            NSLog(@"[ZT-Tunnel] Attempting dlsym fallback for NEProviderMain...");
            typedef int (*NEProviderMainFunc)(int, char **);
            void *handle = dlopen(NULL, RTLD_NOW);
            if (handle) {
                NEProviderMainFunc fn = (NEProviderMainFunc)dlsym(handle, "NEProviderMain");
                if (fn) {
                    NSLog(@"[ZT-Tunnel] NEProviderMain found via dlsym, calling...");
                    return fn(argc, argv);
                }
            }
            NSLog(@"[ZT-Tunnel] FATAL: No entry point found, running NSRunLoop fallback");
            [[NSRunLoop currentRunLoop] run];
        }
    }
    return 0;
}
