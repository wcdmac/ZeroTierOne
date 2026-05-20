#import <Foundation/Foundation.h>

extern int NEProviderMain(int argc, char **argv) __attribute__((visibility("default")));

int main(int argc, char *argv[]) {
    return NEProviderMain(argc, argv);
}
