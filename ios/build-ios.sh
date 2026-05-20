#!/bin/bash
set -e

MIN_VERSION="15.0"
ARCH="arm64"
APP_NAME="ZeroTierOne"
TUNNEL_NAME="ZeroTierTunnel"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

echo "=== Building ZeroTier One iOS App with NEPacketTunnelProvider (xcodebuild) ==="

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "SDK: $SDK"
echo "Architecture: $ARCH"
echo "Min iOS Version: $MIN_VERSION"

echo ""
echo "=== Step 1: Generate Xcode project ==="
python3 "$PROJECT_DIR/generate_xcode_project.py"
echo "Xcode project generated"

echo ""
echo "=== Step 2: Build extension with xcodebuild ==="
xcodebuild \
    -project "$PROJECT_DIR/ZeroTierOne.xcodeproj" \
    -target ZeroTierTunnel \
    -configuration Release \
    -sdk iphoneos \
    -arch arm64 \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    IPHONEOS_DEPLOYMENT_TARGET=$MIN_VERSION \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    ENABLE_BITCODE=NO \
    DEBUG_INFORMATION_FORMAT=dwarf \
    build \
    2>&1 | tail -30

echo ""
echo "=== Step 3: Build main app with xcodebuild ==="
xcodebuild \
    -project "$PROJECT_DIR/ZeroTierOne.xcodeproj" \
    -target ZeroTierOne \
    -configuration Release \
    -sdk iphoneos \
    -arch arm64 \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    IPHONEOS_DEPLOYMENT_TARGET=$MIN_VERSION \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    ENABLE_BITCODE=NO \
    DEBUG_INFORMATION_FORMAT=dwarf \
    build \
    2>&1 | tail -30

echo ""
echo "=== Step 4: Find and assemble build products ==="
APPEX_PATH=$(find "$BUILD_DIR/DerivedData" -name "ZeroTierTunnel.appex" -type d | head -1)
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "ZeroTierOne.app" -type d ! -path "*/ZeroTierTunnel.appex/*" | head -1)

echo "Extension path: $APPEX_PATH"
echo "App path: $APP_PATH"

FINAL_APP_DIR="$BUILD_DIR/$APP_NAME.app"
rm -rf "$FINAL_APP_DIR"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Main app not found in DerivedData!"
    echo "Searching for build products..."
    find "$BUILD_DIR/DerivedData" -name "*.app" -type d 2>/dev/null | head -10
    exit 1
fi

cp -R "$APP_PATH" "$FINAL_APP_DIR"
echo "Main app copied"

if [ -n "$APPEX_PATH" ] && [ -d "$APPEX_PATH" ]; then
    mkdir -p "$FINAL_APP_DIR/PlugIns"
    cp -R "$APPEX_PATH" "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex"
    echo "Extension copied to PlugIns"
else
    echo "WARNING: Extension not found, searching..."
    find "$BUILD_DIR/DerivedData" -name "*.appex" -type d 2>/dev/null | head -10
fi

echo ""
echo "=== Step 5: Copy resources ==="
if [ -d "$PROJECT_DIR/ZeroTierOne/Assets.xcassets" ]; then
    cp -R "$PROJECT_DIR/ZeroTierOne/Assets.xcassets" "$FINAL_APP_DIR/Assets.xcassets"
fi

mkdir -p "$FINAL_APP_DIR/zh-Hans.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" ]; then
    cp "$PROJECT_DIR/ZeroTierOne/zh-Hans.lproj/Localizable.strings" "$FINAL_APP_DIR/zh-Hans.lproj/Localizable.strings"
fi

mkdir -p "$FINAL_APP_DIR/en.lproj"
if [ -f "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" ]; then
    cp "$PROJECT_DIR/ZeroTierOne/en.lproj/Localizable.strings" "$FINAL_APP_DIR/en.lproj/Localizable.strings"
fi

echo ""
echo "=== Step 6: Re-sign with entitlements ==="
if [ -d "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex" ]; then
    codesign --force --sign - \
        --entitlements "$PROJECT_DIR/ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel.entitlements" \
        "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex"
    echo "Extension re-signed with entitlements"
fi

codesign --force --sign - \
    --entitlements "$PROJECT_DIR/ZeroTierOne/ZeroTierOne.entitlements" \
    "$FINAL_APP_DIR"
echo "Main app re-signed with entitlements"

echo ""
echo "=== Step 7: Verify ==="
echo "--- App bundle contents ---"
find "$FINAL_APP_DIR" -type f | while read f; do
    SIZE=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo "?")
    echo "  $SIZE bytes  ${f#$FINAL_APP_DIR/}"
done

echo "--- Main executable info ---"
file "$FINAL_APP_DIR/$APP_NAME" 2>/dev/null || true

echo "--- Extension executable info ---"
if [ -d "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex" ]; then
    file "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" 2>/dev/null || true
fi

echo "--- Extension linked libraries ---"
if [ -f "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" ]; then
    otool -L "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" 2>/dev/null || true
fi

echo "--- Extension undefined symbols ---"
if [ -f "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" ]; then
    nm -u "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex/$TUNNEL_NAME" 2>/dev/null | grep -i "NEProvider" || echo "No NEProvider undefined symbols"
fi

echo "--- Code signature verification ---"
codesign -dvv "$FINAL_APP_DIR" 2>&1 | head -15 || true
if [ -d "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex" ]; then
    codesign -dvv "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex" 2>&1 | head -15 || true
fi

echo "--- Entitlements ---"
codesign -d --entitlements - "$FINAL_APP_DIR" 2>&1 | head -20 || true
if [ -d "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex" ]; then
    codesign -d --entitlements - "$FINAL_APP_DIR/PlugIns/$TUNNEL_NAME.appex" 2>&1 | head -20 || true
fi

APP_SIZE=$(du -sh "$FINAL_APP_DIR" | cut -f1)
echo "=== App bundle total size: $APP_SIZE ==="
echo "=== Build complete: $FINAL_APP_DIR ==="
