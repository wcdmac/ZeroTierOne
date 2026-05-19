CC=clang
CXX=clang++
TOPDIR=$(shell pwd)

INCLUDES=-I$(TOPDIR) -isystem $(TOPDIR)/ext -I$(TOPDIR)/include -I$(TOPDIR)/ext/prometheus-cpp-lite-1.0/core/include -I$(TOPDIR)/ext/prometheus-cpp-lite-1.0/simpleapi/include -I$(TOPDIR)/ext/prometheus-cpp-lite-1.0/3rdparty/http-client-lite/include
DEFS=-DZT_BUILD_PLATFORM=5 -DZT_BUILD_ARCHITECTURE=2
LIBS=

IOS_VERSION_MIN=15.0
ARCH_FLAGS=-arch arm64
SYSROOT=$(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

DEFS+=-DZT_BUILD_PLATFORM=5 -DZT_BUILD_ARCHITECTURE=2

include objects.mk

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

clean:
	rm -f *.a *.o node/*.o osdep/*.o

FORCE:
