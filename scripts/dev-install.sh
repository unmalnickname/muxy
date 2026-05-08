#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Building Muxy (release)"
swift build -c release --product Muxy

SPM_BUILD_DIR=$(swift build -c release --show-bin-path)
BUILD_NUM=$(git -C "$PROJECT_ROOT" rev-list --count HEAD)

# Kill running Muxy first, then clean old installs
echo "==> Killing old Muxy instances"
killall Muxy 2>/dev/null || true
sleep 1

echo "==> Removing old Muxy.app instances"
rm -rf /Applications/Muxy.app
rm -rf ~/Desktop/Muxy.app
rm -rf ~/Downloads/Muxy.app

# Create bundle
APP_BUNDLE="/Applications/Muxy.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Binary
cp "$SPM_BUILD_DIR/Muxy" "$APP_BUNDLE/Contents/MacOS/Muxy"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Muxy"

# Info.plist
cp "$PROJECT_ROOT/Muxy/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.26.0" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP_BUNDLE/Contents/Info.plist"

# App icon
"$SCRIPT_DIR/create-icns.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Resources bundle
if [ -d "$SPM_BUILD_DIR/Muxy_Muxy.bundle" ]; then
    cp -R "$SPM_BUILD_DIR/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi

# Compile asset catalog -> Assets.car
xcrun actool \
    "$SPM_BUILD_DIR/Muxy_Muxy.bundle/Assets.xcassets" \
    --compile "$APP_BUNDLE/Contents/Resources/" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist /tmp/muxy-partial.plist 2>/dev/null

# Embed Sparkle (skip if missing — dev builds work without auto-update)
SPARKLE_SRC="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    cp -R "$SPARKLE_SRC" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --sign - "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi

# Sign with ad-hoc + entitlements
codesign --force --deep --sign - \
    --entitlements "$PROJECT_ROOT/Muxy/Muxy.entitlements" \
    "$APP_BUNDLE" 2>/dev/null

# Register with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" 2>/dev/null || true

echo "==> Installed: $APP_BUNDLE"
echo "    Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
echo "    Build:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")"

echo "==> Launching..."
open "$APP_BUNDLE"
echo "    PID: $(pgrep -x Muxy || echo 'starting...')"
