#!/bin/bash
set -e

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_VERSION="15.0"
ARCH="arm64"
SCHEME="ZeroTierOne"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$SCHEME.app"

echo "=== Building ZeroTier One iOS App ==="
echo "SDK: $SDK"
echo "Architecture: $ARCH"
echo "Min iOS Version: $MIN_VERSION"
echo "Project Dir: $PROJECT_DIR"
echo "Root Dir: $ROOT_DIR"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$APP_DIR"

echo "=== Compiling Swift sources ==="

SWIFT_SOURCES=(
    "$PROJECT_DIR/ZeroTierOne/AppDelegate.swift"
    "$PROJECT_DIR/ZeroTierOne/SceneDelegate.swift"
    "$PROJECT_DIR/ZeroTierOne/ViewController.swift"
)

OBJC_SOURCES=(
    "$PROJECT_DIR/ZeroTierOne/ZeroTierBridge.mm"
)

swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -O \
    -module-name ZeroTierOne \
    -emit-module \
    -emit-module-path "$BUILD_DIR/ZeroTierOne.swiftmodule" \
    -parse-as-library \
    -F "$SDK/System/Library/Frameworks" \
    -I "$BUILD_DIR" \
    -import-objc-header "$PROJECT_DIR/ZeroTierOne/ZeroTierOne-Bridging-Header.h" \
    -o "$BUILD_DIR/ZeroTierOne" \
    "${SWIFT_SOURCES[@]}" \
    "${OBJC_SOURCES[@]}" \
    -L "$ROOT_DIR" \
    -lzerotiercore-ios \
    -lc++ \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore

echo "=== Creating app bundle ==="

cp "$BUILD_DIR/ZeroTierOne" "$APP_DIR/ZeroTierOne"

cp "$PROJECT_DIR/ZeroTierOne/Info.plist" "$APP_DIR/Info.plist"

cp -R "$PROJECT_DIR/ZeroTierOne/Assets.xcassets" "$APP_DIR/Assets.xcassets"

mkdir -p "$APP_DIR/Base.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/Base.lproj/Main.storyboard" ]; then
    cp "$PROJECT_DIR/ZeroTierOne/Base.lproj/Main.storyboard" "$APP_DIR/Base.lproj/Main.storyboard"
fi
if [ -f "$PROJECT_DIR/ZeroTierOne/Base.lproj/LaunchScreen.storyboard" ]; then
    cp "$PROJECT_DIR/ZeroTierOne/Base.lproj/LaunchScreen.storyboard" "$APP_DIR/Base.lproj/LaunchScreen.storyboard"
fi

mkdir -p "$APP_DIR/zh-Hans.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" ]; then
    cp "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" "$APP_DIR/zh-Hans.lproj/Localizable.strings"
fi

mkdir -p "$APP_DIR/en.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" ]; then
    cp "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" "$APP_DIR/en.lproj/Localizable.strings"
fi

echo "=== Verifying app bundle ==="
ls -la "$APP_DIR/"
file "$APP_DIR/ZeroTierOne"

echo "=== Build complete: $APP_DIR ==="
