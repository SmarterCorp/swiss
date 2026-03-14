#!/bin/bash
set -e

APP_NAME="Swiss"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME.app..."

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile SwiftUI app
swiftc \
    -target arm64-apple-macos15 \
    -framework AppKit \
    -framework SwiftUI \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    SwissApp/SwissApp.swift \
    SwissApp/MenuBarView.swift \
    SwissApp/SettingsView.swift \
    SwissApp/CLIBridge.swift

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Swiss</string>
    <key>CFBundleIdentifier</key>
    <string>com.swiss.app</string>
    <key>CFBundleVersion</key>
    <string>1.4.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleExecutable</key>
    <string>Swiss</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -R $APP_BUNDLE /Applications/"
