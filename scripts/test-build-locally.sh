#!/bin/bash
# Build and package a DMG locally for testing
# Usage: ./scripts/test-build-locally.sh [--sign] [--notarize]

set -e

SCHEME="MacInputStats"
PROJECT="MacInputStats.xcodeproj"
APP_NAME="MacInputStats"
BUILD_DIR="$(mktemp -d)"
SIGN=false
NOTARIZE=false

for arg in "$@"; do
    case $arg in
        --sign) SIGN=true ;;
        --notarize) NOTARIZE=true ;;
    esac
done

echo "=== Building $APP_NAME ==="
echo "Build dir: $BUILD_DIR"

# Archive
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# Extract app
APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
EXPORT_DIR="$BUILD_DIR/export"
mkdir -p "$EXPORT_DIR"
cp -R "$APP_PATH" "$EXPORT_DIR/"

# Verify universal binary
echo ""
echo "=== Binary architectures ==="
lipo -info "$EXPORT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Sign if requested
if $SIGN; then
    echo ""
    echo "=== Signing ==="
    codesign --force --sign "Developer ID Application" \
        --options runtime \
        --timestamp \
        --entitlements MacInputStats/MacInputStats.entitlements \
        "$EXPORT_DIR/$APP_NAME.app"
    codesign --verify --deep --strict "$EXPORT_DIR/$APP_NAME.app"
    echo "✓ Signed and verified"
fi

# Notarize if requested
if $NOTARIZE && $SIGN; then
    echo ""
    echo "=== Notarizing ==="
    ditto -c -k --keepParent "$EXPORT_DIR/$APP_NAME.app" "$BUILD_DIR/$APP_NAME.zip"
    xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" \
        --keychain-profile "MacInputStats" \
        --wait --timeout 20m
    xcrun stapler staple "$EXPORT_DIR/$APP_NAME.app"
    echo "✓ Notarized and stapled"
fi

# Create DMG
echo ""
echo "=== Creating DMG ==="
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "Mac Input Stats" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 160 \
        --icon "$APP_NAME.app" 180 170 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 480 170 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$EXPORT_DIR/" || true
fi

# Fallback
if [ ! -f "$DMG_PATH" ]; then
    hdiutil create -volname "Mac Input Stats" \
        -srcfolder "$EXPORT_DIR/" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo ""
echo "=== Done ==="
echo "DMG: $DMG_PATH"
open "$BUILD_DIR"
