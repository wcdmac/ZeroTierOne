#!/bin/bash
set -e

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_VERSION="15.0"
ARCH="arm64"
APP_NAME="ZeroTierOne"
TUNNEL_NAME="ZeroTierTunnel"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
APPEX_DIR="$BUILD_DIR/$TUNNEL_NAME.appex"
OBJ_DIR="$BUILD_DIR/objs"

echo "=== Building ZeroTier One iOS App with NEPacketTunnelProvider ==="
echo "SDK: $SDK"
echo "Architecture: $ARCH"
echo "Min iOS Version: $MIN_VERSION"

echo ""
echo "=== DIAGNOSTIC: Check NetworkExtension framework for NEProviderMain ==="
NE_FW="$SDK/System/Library/Frameworks/NetworkExtension.framework"
if [ -f "$NE_FW/NetworkExtension.tbd" ]; then
    echo "--- Checking TBD file for NEProviderMain ---"
    grep -c "NEProviderMain" "$NE_FW/NetworkExtension.tbd" 2>/dev/null && echo "NEProviderMain FOUND in TBD" || echo "NEProviderMain NOT in TBD file"
    echo "--- All NEProvider* symbols in TBD ---"
    grep "NEProvider" "$NE_FW/NetworkExtension.tbd" 2>/dev/null | head -20 || echo "No NEProvider symbols found"
fi

echo "--- Checking NEProvider.h header for NEProviderMain ---"
NE_HEADER="$SDK/System/Library/Frameworks/NetworkExtension.framework/Headers/NEProvider.h"
if [ -f "$NE_HEADER" ]; then
    echo "NEProvider.h found at: $NE_HEADER"
    grep -n "NEProviderMain\|main\|NEProvider" "$NE_HEADER" | head -30
else
    echo "NEProvider.h NOT found, searching..."
    find "$SDK/System/Library/Frameworks/NetworkExtension.framework" -name "*.h" | head -20
fi

echo "--- Checking NetworkExtension.h umbrella header ---"
NE_UMBRELLA="$SDK/System/Library/Frameworks/NetworkExtension.framework/Headers/NetworkExtension.h"
if [ -f "$NE_UMBRELLA" ]; then
    grep -n "NEProviderMain" "$NE_UMBRELLA" || echo "NEProviderMain NOT in umbrella header"
fi

echo "--- Listing all NetworkExtension headers ---"
ls "$SDK/System/Library/Frameworks/NetworkExtension.framework/Headers/" | head -30

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OBJ_DIR"
mkdir -p "$APP_DIR"
mkdir -p "$APPEX_DIR"

COMMON_FLAGS="-target ${ARCH}-apple-ios${MIN_VERSION} -isysroot $SDK -miphoneos-version-min=$MIN_VERSION"

echo ""
echo "=== Phase 1: Build NetworkExtension (ZeroTierTunnel.appex) ==="
echo ""

echo "--- Step 1: Compile ZTNodeBridge.mm (ObjC++) ---"
clang++ \
    $COMMON_FLAGS \
    -std=c++17 \
    -stdlib=libc++ \
    -fobjc-arc \
    -c \
    -I"$ROOT_DIR" \
    -I"$ROOT_DIR/include" \
    -I"$ROOT_DIR/osdep" \
    -I"$ROOT_DIR/ext" \
    -I"$ROOT_DIR/ext/prometheus-cpp-lite-1.0/core/include" \
    -I"$ROOT_DIR/ext/prometheus-cpp-lite-1.0/simpleapi/include" \
    -I"$ROOT_DIR/ext/prometheus-cpp-lite-1.0/3rdparty/http-client-lite/include" \
    -o "$OBJ_DIR/ZTNodeBridge.o" \
    "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/ZTNodeBridge.mm"
echo "ZTNodeBridge.o compiled successfully"

echo "--- Step 2: Compile main.m (extension entry point with dlopen/dlsym) ---"
clang \
    $COMMON_FLAGS \
    -fobjc-arc \
    -c \
    -o "$OBJ_DIR/main.o" \
    "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/main.m"
echo "main.o compiled successfully"

echo "--- Step 3: Compile and link ZeroTierTunnel ---"
swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -Osize \
    -module-name ZeroTierTunnel \
    -parse-as-library \
    -import-objc-header "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel-Bridging-Header.h" \
    -Xlinker -syslibroot \
    -Xlinker "$SDK" \
    -Xlinker -force_load \
    -Xlinker "$ROOT_DIR/libzerotiercore-ios.a" \
    "$OBJ_DIR/ZTNodeBridge.o" \
    "$OBJ_DIR/main.o" \
    -lc++ \
    -framework NetworkExtension \
    -framework Foundation \
    -o "$APPEX_DIR/$TUNNEL_NAME" \
    "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/PacketTunnelProvider.swift"
echo "ZeroTierTunnel linked successfully"

echo "--- Step 3b: Check ALL undefined symbols in extension ---"
nm -u "$APPEX_DIR/$TUNNEL_NAME" 2>/dev/null | head -50 || echo "nm failed"
echo "--- End undefined symbols ---"

echo "--- Step 4: Create extension PkgInfo ---"
printf "XPC!????" > "$APPEX_DIR/PkgInfo"

echo "--- Step 5: Process extension Info.plist ---"
plutil -convert binary1 -o "$APPEX_DIR/Info.plist" "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/Info.plist" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/Info.plist" "$APPEX_DIR/Info.plist"

echo "--- Step 6: Ad-hoc code sign extension BUNDLE ---"
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel.entitlements" \
    "$APPEX_DIR"
echo "Extension bundle code signature embedded with entitlements"

echo ""
echo "=== Phase 2: Build Main App (ZeroTierOne.app) ==="
echo ""

echo "--- Step 7: Compile and link main app ---"
swiftc \
    -target ${ARCH}-apple-ios${MIN_VERSION} \
    -sdk "$SDK" \
    -Osize \
    -module-name ZeroTierOne \
    -parse-as-library \
    -import-objc-header "$PROJECT_DIR/ZeroTierOne/ZeroTierOne-Bridging-Header.h" \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -framework NetworkExtension \
    -o "$APP_DIR/$APP_NAME" \
    "$PROJECT_DIR/ZeroTierOne/AppDelegate.swift" \
    "$PROJECT_DIR/ZeroTierOne/SceneDelegate.swift" \
    "$PROJECT_DIR/ZeroTierOne/ViewController.swift" \
    "$PROJECT_DIR/ZeroTierOne/ZeroTierBridge.swift"
echo "Main app linked successfully"

echo "--- Step 8: Create PkgInfo ---"
printf "APPL????" > "$APP_DIR/PkgInfo"

echo "--- Step 9: Process Info.plist ---"
plutil -convert binary1 -o "$APP_DIR/Info.plist" "$PROJECT_DIR/ZeroTierOne/Info.plist" 2>/dev/null || \
    cp "$PROJECT_DIR/ZeroTierOne/Info.plist" "$APP_DIR/Info.plist"

echo "--- Step 10: Copy resources ---"
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

echo ""
echo "=== Phase 3: Assemble App Bundle ==="
echo ""

echo "--- Step 11: Embed NetworkExtension into PlugIns ---"
mkdir -p "$APP_DIR/PlugIns"
cp -R "$APPEX_DIR" "$APP_DIR/PlugIns/$TUNNEL_NAME.appex"
echo "Extension embedded in PlugIns directory"

echo "--- Step 12: Ad-hoc code sign main app BUNDLE (after embedding extension) ---"
codesign --force --sign - \
    --entitlements "$PROJECT_DIR/ZeroTierOne/ZeroTierOne.entitlements" \
    "$APP_DIR"
echo "Main app bundle code signature embedded with entitlements (includes extension)"

echo ""
echo "=== Phase 4: Verify ==="
echo ""

echo "--- App bundle contents ---"
find "$APP_DIR" -type f | while read f; do
    SIZE=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "?")
    echo "  $SIZE bytes  ${f#$APP_DIR/}"
done

echo "--- Main executable info ---"
file "$APP_DIR/$APP_NAME"
ls -la "$APP_DIR/$APP_NAME"

echo "--- Extension executable info ---"
file "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME"
ls -la "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME"

echo "--- Extension linked libraries ---"
otool -L "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" 2>/dev/null || true

echo "--- Extension ALL undefined symbols ---"
nm -u "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" 2>/dev/null | head -50 || echo "nm failed"

echo "--- Code signature verification ---"
codesign -dvv "$APP_DIR" 2>&1 | head -20 || true
echo "--- Extension signature verification ---"
codesign -dvv "$APP_DIR/PlugIns/$TUNNEL_NAME.appex" 2>&1 | head -20 || true

echo "--- Main app entitlements ---"
codesign -d --entitlements - "$APP_DIR" 2>&1 | head -25 || true
echo "--- Extension entitlements ---"
codesign -d --entitlements - "$APP_DIR/PlugIns/$TUNNEL_NAME.appex" 2>&1 | head -25 || true

echo "--- Info.plist check ---"
if [ -f "$APP_DIR/Info.plist" ]; then
    echo "Info.plist exists: YES"
else
    echo "Info.plist exists: NO - ERROR!"
fi

echo "--- Extension Info.plist check ---"
if [ -f "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/Info.plist" ]; then
    echo "Extension Info.plist exists: YES"
else
    echo "Extension Info.plist exists: NO - ERROR!"
fi

echo "--- Extension _CodeSignature check ---"
if [ -d "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/_CodeSignature" ]; then
    echo "Extension _CodeSignature directory exists: YES"
    ls -la "$APP_DIR/PlugIns/$TUNNEL_NAME.appex/_CodeSignature/"
else
    echo "Extension _CodeSignature directory exists: NO - WARNING"
fi

echo "--- Main app _CodeSignature check ---"
if [ -d "$APP_DIR/_CodeSignature" ]; then
    echo "Main app _CodeSignature directory exists: YES"
    ls -la "$APP_DIR/_CodeSignature/"
else
    echo "Main app _CodeSignature directory exists: NO - WARNING"
fi

APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo "=== App bundle total size: $APP_SIZE ==="
echo "=== Build complete: $APP_DIR ==="
