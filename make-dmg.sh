#!/usr/bin/env bash
# Build an unsigned TokenCap.dmg for local sharing.
# Recipients will see a Gatekeeper warning and must right-click → Open
# (or allow in System Settings → Privacy & Security) on first launch.

set -euo pipefail

APP_NAME="TokenCap"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Building universal binary (arm64 + x86_64)"
cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64

echo "==> Assembling $APP_NAME.app"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

RESOURCE_BUNDLE=".build/apple/Products/Release/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

echo "==> Creating DMG via hdiutil"
STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo ""
echo "Built: $DMG_PATH"
echo "Size:  $(du -h "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "Note: this DMG is unsigned. Recipients will see a Gatekeeper warning"
echo "on first launch and must right-click → Open, or approve in"
echo "System Settings → Privacy & Security."
