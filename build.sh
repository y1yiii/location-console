#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
OUTPUT_DIR="${1:-$SOURCE_DIR/.build/app}"
APP_DIR="$OUTPUT_DIR/定位控制台.app"
BUILD_DIR="${LOCATION_CONSOLE_BUILD_DIR:-$SOURCE_DIR/.build}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$BUILD_DIR/module-cache" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx swiftc -swift-version 5 -O -parse-as-library \
    -target arm64-apple-macos14.0 -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/module-cache" \
    "$SOURCE_DIR"/Sources/*.swift -o "$APP_DIR/Contents/MacOS/LocationConsole"
cp "$SOURCE_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SOURCE_DIR/使用说明.md" "$APP_DIR/Contents/Resources/使用说明.md"
cp "$SOURCE_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
xcrun --sdk macosx swift -module-cache-path "$BUILD_DIR/module-cache" "$SOURCE_DIR/Icon.swift" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
print "已生成：$APP_DIR"
