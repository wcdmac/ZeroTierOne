#import <Foundation/Foundation.h>

extern int NEProviderMain(int argc, char **argv);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return NEProviderMain(argc, argv);
    }
}
