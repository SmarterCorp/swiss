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
    -framework CoreWLAN \
    -o "$BUILD_DIR/$APP_NAME" \
    Sources/main.swift \
    Sources/DisplayCommand.swift \
    Sources/USBCommand.swift \
    Sources/CursorCommand.swift \
    Sources/TextreamCommand.swift \
    Sources/RSSCommand.swift \
    Sources/BrewDependency.swift \
    Sources/DuaCommand.swift \
    Sources/TopCommand.swift \
    Sources/WiFiCommand.swift \
    Sources/BatteryCommand.swift \
    Sources/PortsCommand.swift \
    Sources/TrashCommand.swift \
    Sources/ClipboardCommand.swift \
    Sources/DockerDependency.swift \
    Sources/TranslateCommand.swift \
    Sources/FeedTranslator.swift \
    Sources/NewsboatConfig.swift \
    Sources/VoiceCommand.swift \
    Sources/PromptCommand.swift \
    Sources/StatusCommand.swift \
    Sources/MaintainCommand.swift \
    Sources/DashCommand.swift \
    Sources/PassCommand.swift \
    Sources/MenuBarCommand.swift \
    Sources/CleanCommand.swift \
    Sources/SleepCommand.swift \
    Sources/TwitterCommand.swift

echo "Build complete: $BUILD_DIR/$APP_NAME"

INSTALL_DIR="/usr/local/bin"

if [[ "$1" == "install" ]]; then
    echo "Installing $APP_NAME to $INSTALL_DIR..."
    cp "$BUILD_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
    echo "Installed! You can now use '$APP_NAME' from anywhere."
else
    echo ""
    echo "To install system-wide, run:"
    echo "  ./build.sh install"
    echo ""
    echo "Commands:"
    echo "  $APP_NAME display off   — disconnect external monitors"
    echo "  $APP_NAME display on    — reconnect external monitors"
    echo "  $APP_NAME usb           — list USB devices"
    echo "  $APP_NAME cursor start  — start cursor teleporter"
    echo "  $APP_NAME cursor stop   — stop cursor teleporter"
    echo "  $APP_NAME rss           — RSS reader (newsboat)"
    echo "  $APP_NAME dua           — disk usage analyzer"
    echo "  $APP_NAME top           — activity monitor"
    echo "  $APP_NAME wifi          — WiFi network info"
    echo "  $APP_NAME battery       — battery status and health"
    echo "  $APP_NAME ports         — list open listening ports"
    echo "  $APP_NAME trash [files] — move to Trash / show info"
    echo "  $APP_NAME clipboard     — copy/paste via stdin/stdout"
fi
