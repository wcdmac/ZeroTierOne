#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdio.h>
#import <string.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[ZT-Tunnel] ========== Extension main() started ==========");
        NSLog(@"[ZT-Tunnel] PID: %d", getpid());
        NSLog(@"[ZT-Tunnel] argc: %d", argc);

        void *neHandle = dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_NOW);
        if (neHandle) {
            NSLog(@"[ZT-Tunnel] NetworkExtension framework loaded successfully");
        } else {
            NSLog(@"[ZT-Tunnel] FATAL: Failed to load NetworkExtension framework: %s", dlerror());
        }

        if (neHandle) {
            typedef int (*NEProviderMainFunc)(int, char **);
            NEProviderMainFunc neProviderMain = (NEProviderMainFunc)dlsym(neHandle, "NEProviderMain");
            if (neProviderMain) {
                NSLog(@"[ZT-Tunnel] NEProviderMain found, calling it...");
                int result = neProviderMain(argc, argv);
                NSLog(@"[ZT-Tunnel] NEProviderMain returned: %d", result);
                return result;
            } else {
                NSLog(@"[ZT-Tunnel] FATAL: NEProviderMain not found in NetworkExtension framework!");
                NSLog(@"[ZT-Tunnel] dlerror: %s", dlerror());
            }
        }

        NSLog(@"[ZT-Tunnel] Falling back to NSRunLoop...");
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
