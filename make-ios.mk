CC=clang
CXX=clang++
TOPDIR=$(shell pwd)

INCLUDES=-I$(TOPDIR) -isystem $(TOPDIR)/ext -I$(TOPDIR)/include
DEFS=-DZT_BUILD_PLATFORM=5 -DZT_BUILD_ARCHITECTURE=2
LIBS=

IOS_VERSION_MIN=15.0
ARCH_FLAGS=-arch arm64
SYSROOT=$(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

ZT_VERSION_MAJOR=$(shell cat version.h | grep -F VERSION_MAJOR | cut -d ' ' -f 3)
ZT_VERSION_MINOR=$(shell cat version.h | grep -F VERSION_MINOR | cut -d ' ' -f 3)
ZT_VERSION_REV=$(shell cat version.h | grep -F VERSION_REVISION | cut -d ' ' -f 3)

DEFS+=-DZT_BUILD_PLATFORM=5 -DZT_BUILD_ARCHITECTURE=2

include objects.mk

override DEFS+=-DZT_NO_TYPE_PUNNING -DZT_USE_ARM32_NEON_ASM_SALSA2012

CORE_OBJS+=ext/arm32-neon-salsa2012-asm/salsa2012.o

CFLAGS=-O3 -fstack-protector-strong $(ARCH_FLAGS) -isysroot $(SYSROOT) -miphoneos-version-min=$(IOS_VERSION_MIN) -flto -fPIE -DNDEBUG -Wall -Wno-unused-private-field $(INCLUDES) $(DEFS)
CXXFLAGS=$(CFLAGS) -std=c++17 -stdlib=libc++

ifeq ($(ZT_DEBUG),1)
	CFLAGS=-Wall -g $(ARCH_FLAGS) -isysroot $(SYSROOT) -miphoneos-version-min=$(IOS_VERSION_MIN) $(INCLUDES) $(DEFS)
	CXXFLAGS=$(CFLAGS) -std=c++17 -stdlib=libc++
	STRIP=echo
else
	STRIP=strip
endif

all: libzerotiercore-ios.a

libzerotiercore-ios.a: $(CORE_OBJS)
	ar rcs libzerotiercore-ios.a $(CORE_OBJS)
	ranlib libzerotiercore-ios.a

ext/arm32-neon-salsa2012-asm/salsa2012.o:
	as -arch arm64 -isysroot $(SYSROOT) -o ext/arm32-neon-salsa2012-asm/salsa2012.o ext/arm32-neon-salsa2012-asm/salsa2012.s

clean:
	rm -f *.a *.o node/*.o osdep/*.o ext/arm32-neon-salsa2012-asm/*.o ext/http-parser/*.o ext/x64-salsa2012-asm/*.o

FORCE:
