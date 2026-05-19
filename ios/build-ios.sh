#!/bin/bash
set -e

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_VERSION="15.0"
ARCH="arm64"
APP_NAME="ZeroTierOne"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
OBJ_DIR="$BUILD_DIR/objs"

echo "=== Building ZeroTier One iOS App ==="
echo "SDK: $SDK"
echo "Architecture: $ARCH"
echo "Min iOS Version: $MIN_VERSION"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OBJ_DIR"
mkdir -p "$APP_DIR"

COMMON_FLAGS="-target ${ARCH}-apple-ios${MIN_VERSION} -isysroot $SDK -miphoneos-version-min=$MIN_VERSION"

echo "=== Step 1: Compile Objective-C++ bridge ==="
clang++ \
    $COMMON_FLAGS \
    -std=c++17 \
    -stdlib=libc++ \
    -fobjc-arc \
    -c \
    -I"$ROOT_DIR/include" \
    -I"$ROOT_DIR/node" \
    -I"$ROOT_DIR/ext" \
    -I"$ROOT_DIR/ext/prometheus-cpp-lite-1.0/core/include" \
    -I"$ROOT_DIR/ext/prometheus-cpp-lite-1.0/simpleapi/include" \
    -I"$ROOT_DIR/ext/prometheus-cpp-lite-1.0/3rdparty/http-client-lite/include" \
    -o "$OBJ_DIR/ZeroTierBridge.o" \
    "$PROJECT_DIR/ZeroTierOne/ZeroTierBridge.mm"

echo "=== Step 2: Compile Swift sources to object files ==="
mkdir -p "$OBJ_DIR/swift"
swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -Osize \
    -module-name ZeroTierOne \
    -parse-as-library \
    -import-objc-header "$PROJECT_DIR/ZeroTierOne/ZeroTierOne-Bridging-Header.h" \
    -emit-object \
    -o "$OBJ_DIR/swift/AppDelegate.o" \
    "$PROJECT_DIR/ZeroTierOne/AppDelegate.swift"

swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -Osize \
    -module-name ZeroTierOne \
    -parse-as-library \
    -import-objc-header "$PROJECT_DIR/ZeroTierOne/ZeroTierOne-Bridging-Header.h" \
    -emit-object \
    -o "$OBJ_DIR/swift/SceneDelegate.o" \
    "$PROJECT_DIR/ZeroTierOne/SceneDelegate.swift"

swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -Osize \
    -module-name ZeroTierOne \
    -parse-as-library \
    -import-objc-header "$PROJECT_DIR/ZeroTierOne/ZeroTierOne-Bridging-Header.h" \
    -emit-object \
    -o "$OBJ_DIR/swift/ViewController.o" \
    "$PROJECT_DIR/ZeroTierOne/ViewController.swift"

echo "=== Step 3: Link executable ==="
SWIFT_OBJS="$OBJ_DIR/swift/AppDelegate.o $OBJ_DIR/swift/SceneDelegate.o $OBJ_DIR/swift/ViewController.o"
swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -L "$ROOT_DIR" \
    -lzerotiercore-ios \
    -lc++ \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -framework SwiftUI \
    -o "$APP_DIR/$APP_NAME" \
    $SWIFT_OBJS \
    "$OBJ_DIR/ZeroTierBridge.o"

echo "=== Step 4: Create PkgInfo ==="
printf "APPL????" > "$APP_DIR/PkgInfo"

echo "=== Step 5: Process Info.plist ==="
plutil -convert binary1 -o "$APP_DIR/Info.plist" "$PROJECT_DIR/ZeroTierOne/Info.plist" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/Info.plist" "$APP_DIR/Info.plist"

echo "=== Step 6: Compile storyboards ==="
if [ -f "$PROJECT_DIR/ZeroTierOne/Base.lproj/Main.storyboard" ]; then
    ibtool \
        --target-device iphone \
        --target-device ipad \
        --minimum-deployment-target $MIN_VERSION \
        --compilation-directory "$APP_DIR/Base.lproj" \
        --errors --warnings --notices \
        "$PROJECT_DIR/ZeroTierOne/Base.lproj/Main.storyboard" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/Base.lproj/Main.storyboard" "$APP_DIR/Base.lproj/Main.storyboard"
fi

if [ -f "$PROJECT_DIR/ZeroTierOne/Base.lproj/LaunchScreen.storyboard" ]; then
    ibtool \
        --target-device iphone \
        --target-device ipad \
        --minimum-deployment-target $MIN_VERSION \
        --compilation-directory "$APP_DIR/Base.lproj" \
        --errors --warnings --notices \
        "$PROJECT_DIR/ZeroTierOne/Base.lproj/LaunchScreen.storyboard" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/Base.lproj/LaunchScreen.storyboard" "$APP_DIR/Base.lproj/LaunchScreen.storyboard"
fi

echo "=== Step 7: Copy assets and resources ==="
cp -R "$PROJECT_DIR/ZeroTierOne/Assets.xcassets" "$APP_DIR/Assets.xcassets"

mkdir -p "$APP_DIR/zh-Hans.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" ]; then
    plutil -convert binary1 -o "$APP_DIR/zh-Hans.lproj/Localizable.strings" "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" "$APP_DIR/zh-Hans.lproj/Localizable.strings"
fi

mkdir -p "$APP_DIR/en.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" ]; then
    plutil -convert binary1 -o "$APP_DIR/en.lproj/Localizable.strings" "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" "$APP_DIR/en.lproj/Localizable.strings"
fi

echo "=== Step 8: Verify app bundle ==="
echo "--- App bundle contents ---"
find "$APP_DIR" -type f | while read f; do
    SIZE=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "?")
    echo "  $SIZE bytes  ${f#$APP_DIR/}"
done

echo "--- Executable info ---"
file "$APP_DIR/$APP_NAME"
ls -la "$APP_DIR/$APP_NAME"

echo "--- Info.plist check ---"
if [ -f "$APP_DIR/Info.plist" ]; then
    echo "Info.plist exists: YES"
    plutil -p "$APP_DIR/Info.plist" 2>/dev/null | head -5 || echo "(binary plist)"
else
    echo "Info.plist exists: NO - ERROR!"
fi

APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo "=== App bundle total size: $APP_SIZE ==="
echo "=== Build complete: $APP_DIR ==="
