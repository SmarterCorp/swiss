import Foundation

private let domain = "com.apple.controlcenter"

func runMenuBarCommand(args: [String]) {
    guard let action = args.first else {
        listMenuBarItems()
        return
    }

    switch action {
    case "list", "ls":
        listMenuBarItems()
    case "hide":
        guard args.count >= 2 else {
            fputs("Usage: swiss menubar hide <item>\n", stderr)
            exit(1)
        }
        setVisibility(item: args[1], visible: false)
    case "show":
        guard args.count >= 2 else {
            fputs("Usage: swiss menubar show <item>\n", stderr)
            exit(1)
        }
        setVisibility(item: args[1], visible: true)
    case "reset":
        resetPositions()
    case "help", "-h", "--help":
        printMenuBarUsage()
    default:
        fputs("Unknown menubar subcommand: \(action)\n", stderr)
        printMenuBarUsage()
        exit(1)
    }
}

private func printMenuBarUsage() {
    print("Usage: swiss menubar <command>")
    print("")
    print("Commands:")
    print("  list                — show all menu bar items")
    print("  show <item>         — show an item in the menu bar")
    print("  hide <item>         — hide an item from the menu bar")
    print("  reset               — reset all icon positions")
    print("")
    print("Items: WiFi, Bluetooth, Battery, Sound, Display, FaceTime,")
    print("       NowPlaying, ScreenMirroring, BentoBox, UserSwitcher")
}

// MARK: - List

// Known system menu bar items
private let knownSystemItems = [
    "WiFi", "Bluetooth", "Battery", "Sound", "Clock",
    "BentoBox", "Display", "FaceTime", "NowPlaying",
    "ScreenMirroring", "UserSwitcher", "Accessibility",
    "KeyboardBrightness", "AirDrop",
]

private func listMenuBarItems() {
    guard let output = captureDefaults(["read", domain]) else {
        fputs("Error: Could not read menu bar settings.\n", stderr)
        exit(1)
    }

    let lines = output.components(separatedBy: "\n")

    // Collect all items from both Visible and VisibleCC keys
    var visibleMap: [String: Bool] = [:]   // from "NSStatusItem Visible X"
    var visibleCCMap: [String: Bool] = [:] // from "NSStatusItem VisibleCC X"
    var positionMap: [String: Int] = [:]

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: "=")
        guard parts.count == 2 else { continue }
        let keyPart = parts[0].trimmingCharacters(in: .whitespaces)
        let valPart = parts[1].trimmingCharacters(in: .init(charactersIn: " ;"))

        if trimmed.contains("NSStatusItem Visible ") && !trimmed.contains("VisibleCC") && !trimmed.contains("Preferred") {
            let name = keyPart
                .replacingOccurrences(of: "\"NSStatusItem Visible ", with: "")
                .replacingOccurrences(of: "\"", with: "")
            if !name.hasPrefix("Item-") {
                visibleMap[name] = valPart == "1"
            }
        } else if trimmed.contains("NSStatusItem VisibleCC ") {
            let name = keyPart
                .replacingOccurrences(of: "\"NSStatusItem VisibleCC ", with: "")
                .replacingOccurrences(of: "\"", with: "")
            visibleCCMap[name] = valPart == "1"
        } else if trimmed.contains("NSStatusItem Preferred Position ") {
            let name = keyPart
                .replacingOccurrences(of: "\"NSStatusItem Preferred Position ", with: "")
                .replacingOccurrences(of: "\"", with: "")
            positionMap[name] = Int(valPart)
        }
    }

    // Build unified item list
    var allNames = Set(knownSystemItems)
    allNames.formUnion(visibleMap.keys)
    allNames.formUnion(visibleCCMap.keys.filter { !$0.contains("-") }) // skip BentoBox-0

    var items: [(name: String, visible: Bool, position: Int?)] = []
    for name in allNames {
        // Item is visible if: explicitly Visible=1, or VisibleCC=1 and not explicitly Visible=0
        let explicit = visibleMap[name]
        let cc = visibleCCMap[name]
        let visible: Bool
        if let v = explicit {
            visible = v
        } else if let c = cc {
            visible = c
        } else {
            // Known system item with no keys — check if it has a position (means it's shown)
            visible = positionMap[name] != nil
        }
        items.append((name: name, visible: visible, position: positionMap[name]))
    }

    // Sort: shown first (by position), then hidden alphabetically
    items.sort { a, b in
        if a.visible != b.visible { return a.visible }
        if a.visible {
            return (a.position ?? 9999) < (b.position ?? 9999)
        }
        return a.name < b.name
    }

    if items.isEmpty {
        print("No menu bar items found.")
        return
    }

    let maxName = max(items.map { $0.name.count }.max() ?? 10, 16)
    print("Menu bar items:")
    print("")
    for item in items {
        let icon = item.visible ? "[+]" : "[-]"
        let name = item.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
        let pos = item.position.map { "pos: \($0)" } ?? ""
        print("  \(icon) \(name)  \(pos)")
    }
}

// MARK: - Show / Hide

private func setVisibility(item: String, visible: Bool) {
    let key = "NSStatusItem Visible \(item)"
    let value = visible ? "1" : "0"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["write", domain, key, "-int", value]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fputs("Error: Failed to set \(item) visibility.\n", stderr)
        exit(1)
    }

    restartControlCenter()
    print("\(item): \(visible ? "shown" : "hidden")")
}

// MARK: - Reset positions

private func resetPositions() {
    guard let output = captureDefaults(["read", domain]) else { return }

    let lines = output.components(separatedBy: "\n")
    var deleted = 0

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"NSStatusItem Preferred Position") {
            let parts = trimmed.components(separatedBy: "=")
            guard let keyPart = parts.first else { continue }
            let key = keyPart.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["delete", domain, key]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            deleted += 1
        }
    }

    restartControlCenter()
    print("Reset \(deleted) icon positions.")
}

// MARK: - Helpers

private func restartControlCenter() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["ControlCenter"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

private func captureDefaults(_ args: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = args
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()

    var data = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    process.waitUntilExit()
    group.wait()

    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}
