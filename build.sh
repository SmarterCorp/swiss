#!/bin/bash
set -e

APP_NAME="swiss"
BUILD_DIR="build"

echo "Building $APP_NAME..."

mkdir -p "$BUILD_DIR"

swiftc \
    -target arm64-apple-macos13 \
    -framework CoreGraphics \
    -framework CoreDisplay \
    -framework IOKit \
    -framework AppKit \
    -o "$BUILD_DIR/$APP_NAME" \
    Sources/main.swift \
    Sources/DisplayCommand.swift \
    Sources/USBCommand.swift \
    Sources/CursorCommand.swift \
    Sources/TextreamCommand.swift \
    Sources/RSSCommand.swift \
    Sources/BrewDependency.swift \
    Sources/DuaCommand.swift \
    Sources/TopCommand.swift

echo "Build complete: $BUILD_DIR/$APP_NAME"
echo ""
echo "Commands:"
echo "  ./$BUILD_DIR/$APP_NAME display off   — disconnect external monitors"
echo "  ./$BUILD_DIR/$APP_NAME display on    — reconnect external monitors"
echo "  ./$BUILD_DIR/$APP_NAME usb           — list USB devices"
echo "  ./$BUILD_DIR/$APP_NAME cursor start  — start cursor teleporter"
echo "  ./$BUILD_DIR/$APP_NAME cursor stop   — stop cursor teleporter"
echo "  ./$BUILD_DIR/$APP_NAME rss           — RSS reader (newsboat)"
echo "  ./$BUILD_DIR/$APP_NAME dua           — disk usage analyzer"
echo "  ./$BUILD_DIR/$APP_NAME top           — activity monitor"
