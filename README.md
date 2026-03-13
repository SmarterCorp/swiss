# swiss — CLI multitool for macOS

A lightweight command-line utility for managing displays, USB devices, multi-monitor cursor navigation, RSS feeds, and more on macOS. Written in Swift, compiled with `swiftc`, no Xcode project required.

## Build

```bash
bash build.sh
```

Produces `build/swiss`. Target: `arm64-apple-macos13` (Apple Silicon).

Linked frameworks: CoreGraphics, CoreDisplay, IOKit, AppKit.

## Commands

### `swiss display off`

Disconnects all external monitors (the built-in display stays on).

Under the hood it uses the private API `CGSConfigureDisplayEnabled` — the same mechanism macOS uses internally. Each disconnected display ID is saved to `~/.swiss-display-state` so they can be reconnected later.

```
$ swiss display off
Disconnecting DELL U2723QE (id: 725288513)...
  Done

To reconnect: swiss display on
```

### `swiss display on`

Reconnects monitors previously disconnected with `swiss display off`. Reads display IDs from `~/.swiss-display-state`, re-enables each one, then deletes the state file.

```
$ swiss display on
Reconnecting display (id: 725288513)...
  Done

Done.
```

If there is no state file (nothing was disconnected), the command exits with an error.

### `swiss usb`

Lists all connected USB devices with detailed information: device name, vendor, product ID, speed protocol, serial number, power draw, and location ID.

Uses two detection methods:
1. **system_profiler** (`SPUSBHostDataType`) — primary, works on macOS 26+, supports nested device hierarchy.
2. **IOKit** (`IOUSBHostDevice`) — fallback, queries the IO registry directly.

Output is a tree with `├──` / `└──` connectors:

```
USB Devices (3):

├── CalDigit TS4
│   Vendor: CalDigit (0x2188)  Product: 0x0100
│   Speed: USB 3.1 SuperSpeed+ (10 Gbps)
│   Serial: F20123456
│   Power: 0 mA
│   Location: 0x02100000
│
├── Keyboard
│   Vendor: Apple Inc. (0x05ac)  Product: 0x0267
│   Speed: USB 2.0 High Speed (480 Mbps)
│   Power: 500 mA
│   Location: 0x02130000
│
└── ...
```

### `swiss cursor start`

Starts a background daemon that listens for **Command+2** and teleports the mouse cursor between displays.

**How it works:**

1. The daemon creates a [CGEventTap](https://developer.apple.com/documentation/coregraphics/cgevent) that intercepts keyboard events at the session level.
2. When Command+2 is detected (keycode 19 + Command flag, no other modifiers):
   - The current cursor position is saved for the current display.
   - The cursor jumps to the **next display** in the cycle (sorted left-to-right by screen position).
   - If the target display was visited before, the cursor returns to the **exact saved position**. Otherwise it lands at the **center** of the screen.
   - The original Command+2 keypress is suppressed (not passed to apps).
3. The daemon writes its PID to `~/.swiss-cursor.pid` and runs `CFRunLoopRun()` to stay alive.
4. Handles SIGTERM and SIGINT — cleans up the PID file on exit.

```
$ swiss cursor start &
Cursor teleporter running (PID 12345). Press Command+2 to teleport between displays.
```

Display cycling order: screens are sorted by X coordinate (left to right), then Y coordinate. After the last display, it wraps back to the first.

**Requires Accessibility permission.** If the event tap fails to create, the daemon prints instructions:

```
Failed to create event tap.
Grant Accessibility permission: System Settings → Privacy & Security → Accessibility
```

You need to add `swiss` (or Terminal / your terminal emulator) to the Accessibility list.

### `swiss cursor stop`

Stops a running cursor teleporter daemon.

1. Reads PID from `~/.swiss-cursor.pid`.
2. Sends SIGTERM to the process.
3. Removes the PID file.

```
$ swiss cursor stop
Cursor teleporter stopped (PID 12345).
```

### `swiss textream [text|file]`

Opens the Textream teleprompter app via its URL scheme (`textream://`).

- `swiss textream` — opens Textream with no text.
- `swiss textream "Hello world"` — opens Textream with the given text.
- `swiss textream path/to/file.txt` — reads the file and sends its contents to Textream.
- `echo "Hello" | swiss textream` — reads text from stdin (pipe).

Requires the Textream app to be installed.

### `swiss rss [args]`

Terminal RSS reader. Wraps [newsboat](https://newsboat.org/) — auto-installs via Homebrew if not present.

- `swiss rss` — launches newsboat.
- `swiss rss <args>` — passes arguments directly to `newsboat`.

### `swiss dua [args]`

Disk usage analyzer. Wraps [dua-cli](https://github.com/Byron/dua-cli) — auto-installs via Homebrew if not present.

- `swiss dua` — launches interactive mode (`dua interactive`).
- `swiss dua <args>` — passes arguments directly to `dua`.

### `swiss top [args]`

Activity monitor. Wraps [bottom](https://github.com/ClementTsang/bottom) (`btm`) — auto-installs via Homebrew if not present.

- `swiss top` — launches `btm` with no arguments.
- `swiss top <args>` — passes arguments directly to `btm`.

## File structure

```
Sources/
  main.swift              — CLI entry point and command dispatcher
  DisplayCommand.swift    — display on/off logic (private CoreGraphics API)
  USBCommand.swift        — USB device listing (system_profiler + IOKit)
  CursorCommand.swift     — cursor teleporter daemon (CGEventTap + AppKit)
  TextreamCommand.swift   — Textream app launcher via URL scheme
  RSSCommand.swift        — newsboat wrapper
  BrewDependency.swift    — Auto-install Homebrew dependencies
  DuaCommand.swift        — dua-cli wrapper
  TopCommand.swift        — bottom (btm) wrapper
build.sh                  — single-file build script
```

## State files

| File | Created by | Purpose |
|---|---|---|
| `~/.swiss-display-state` | `display off` | Stores disconnected display IDs (one per line) |
| `~/.swiss-cursor.pid` | `cursor start` | Daemon PID for `cursor stop` |
