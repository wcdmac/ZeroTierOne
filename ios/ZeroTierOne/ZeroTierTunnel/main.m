#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef int (*NEProviderMainFunc)(int, char **);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NEProviderMainFunc neProviderMain = (NEProviderMainFunc)dlsym(RTLD_DEFAULT, "NEProviderMain");
        if (neProviderMain) {
            return neProviderMain(argc, argv);
        }
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
