#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <dlfcn.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        typedef int (*NEProviderMainFunc)(int, char **);
        NEProviderMainFunc neProviderMain = (NEProviderMainFunc)dlsym(RTLD_DEFAULT, "NEProviderMain");
        if (neProviderMain) {
            return neProviderMain(argc, argv);
        }
        NSLog(@"[ZT-Tunnel] FATAL: NEProviderMain not found, running fallback loop");
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
