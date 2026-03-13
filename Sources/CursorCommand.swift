import Foundation
import AppKit
import CoreGraphics

// MARK: - Cursor Teleporter Daemon

private let pidFilePath = NSString("~/.swiss-cursor.pid").expandingTildeInPath

/// Stored last-known cursor position per display
private var savedPositions: [CGDirectDisplayID: CGPoint] = [:]

func runCursorCommand(args: [String]) {
    guard let subcommand = args.first else {
        print("Usage: swiss cursor <start|stop>")
        exit(1)
    }

    switch subcommand {
    case "start":
        cursorStart()
    case "stop":
        cursorStop()
    default:
        print("Unknown cursor subcommand: \(subcommand)")
        print("Usage: swiss cursor <start|stop>")
        exit(1)
    }
}

// MARK: - Start

private func cursorStart() {
    // Write PID file
    let pid = ProcessInfo.processInfo.processIdentifier
    do {
        try "\(pid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)
    } catch {
        print("Failed to write PID file: \(error)")
        exit(1)
    }

    // Clean up PID file on exit
    signal(SIGTERM) { _ in
        try? FileManager.default.removeItem(atPath: pidFilePath)
        exit(0)
    }
    signal(SIGINT) { _ in
        try? FileManager.default.removeItem(atPath: pidFilePath)
        exit(0)
    }

    // Create event tap for keyDown events
    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

    guard let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: eventTapCallback,
        userInfo: nil
    ) else {
        print("Failed to create event tap.")
        print("Grant Accessibility permission: System Settings → Privacy & Security → Accessibility")
        try? FileManager.default.removeItem(atPath: pidFilePath)
        exit(1)
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    print("Cursor teleporter running (PID \(pid)). Press Command+2 to teleport between displays.")
    CFRunLoopRun()
}

// MARK: - Event Tap Callback

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if it gets disabled by the system
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    // Command+2: keycode 19 is the '2' key
    guard keycode == 19, flags.contains(.maskCommand) else {
        return Unmanaged.passRetained(event)
    }

    // Don't trigger if other modifiers are held (Shift, Option, Control)
    let extraModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl]
    guard flags.intersection(extraModifiers).isEmpty else {
        return Unmanaged.passRetained(event)
    }

    teleportCursor()

    // Suppress the keypress
    return nil
}

// MARK: - Teleport Logic

private func teleportCursor() {
    let screens = NSScreen.screens
    guard screens.count > 1 else { return }

    // Build sorted display list (by x position, then y)
    let sortedScreens = screens.sorted { a, b in
        if a.frame.origin.x != b.frame.origin.x {
            return a.frame.origin.x < b.frame.origin.x
        }
        return a.frame.origin.y < b.frame.origin.y
    }

    // Current mouse location (AppKit coordinates: origin at bottom-left)
    let mouseLocation = NSEvent.mouseLocation

    // Find which screen the cursor is on
    guard let currentIndex = sortedScreens.firstIndex(where: { $0.frame.contains(mouseLocation) }) else {
        return
    }

    let currentScreen = sortedScreens[currentIndex]
    let currentDisplayID = displayID(for: currentScreen)

    // Save current position for current display (in global CG coordinates)
    let cgMousePos = CGEvent(source: nil)?.location ?? CGPoint.zero
    savedPositions[currentDisplayID] = cgMousePos

    // Next display in cycle
    let nextIndex = (currentIndex + 1) % sortedScreens.count
    let targetScreen = sortedScreens[nextIndex]
    let targetDisplayID = displayID(for: targetScreen)

    // Restore saved position or use center of target display
    let targetPoint: CGPoint
    if let saved = savedPositions[targetDisplayID] {
        targetPoint = saved
    } else {
        // Center of target screen in CG coordinates (origin top-left)
        let frame = targetScreen.frame
        // Convert from AppKit (bottom-left origin) to CG (top-left origin)
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let cgY = mainScreenHeight - frame.origin.y - frame.height / 2
        targetPoint = CGPoint(x: frame.origin.x + frame.width / 2, y: cgY)
    }

    CGWarpMouseCursorPosition(targetPoint)
    // Post a dummy mouse move so the system updates the cursor context
    if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: targetPoint, mouseButton: .left) {
        moveEvent.post(tap: .cghidEventTap)
    }
}

private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
    return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
}

// MARK: - Stop

private func cursorStop() {
    guard FileManager.default.fileExists(atPath: pidFilePath) else {
        print("Cursor teleporter is not running (no PID file).")
        exit(1)
    }

    guard let pidString = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
          let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        print("Failed to read PID file.")
        exit(1)
    }

    kill(pid, SIGTERM)
    try? FileManager.default.removeItem(atPath: pidFilePath)
    print("Cursor teleporter stopped (PID \(pid)).")
}
