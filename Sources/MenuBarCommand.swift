import Foundation
import AppKit

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

// Friendly names for known bundle IDs
private let bundleNames: [String: String] = [
    "com.apple.controlcenter": "Control Center",
    "com.apple.Spotlight": "Spotlight",
    "com.apple.TextInputMenuAgent": "Input Menu",
    "com.apple.Passwords.MenuBarExtra": "Passwords",
    "com.apple.systemuiserver": "System UI",
]

// Known Control Center sub-items
private let knownCCItems = [
    "WiFi", "Bluetooth", "Battery", "Sound", "Clock",
    "BentoBox", "Display", "FaceTime", "NowPlaying",
    "ScreenMirroring", "UserSwitcher",
]

private func listMenuBarItems() {
    // Fast scan: grep plist files for NSStatusItem instead of reading 900+ domains
    let prefsDir = NSHomeDirectory() + "/Library/Preferences"
    // grep returns exit 1 on binary plist files but still outputs matches
    let grepOutput = captureCmd("/usr/bin/grep", args: ["-rl", "NSStatusItem", prefsDir], allowFailure: true) ?? ""
    guard !grepOutput.isEmpty else {
        fputs("Error: No menu bar items found.\n", stderr)
        exit(1)
    }

    let domains = grepOutput.components(separatedBy: "\n")
        .filter { !$0.isEmpty }
        .map { path -> String in
            // Convert /path/to/com.example.app.plist -> com.example.app
            let filename = (path as NSString).lastPathComponent
            return filename.replacingOccurrences(of: ".plist", with: "")
        }

    struct MenuBarItem {
        let name: String
        let domain: String
        var position: Int?
        var visible: Bool
    }

    var items: [MenuBarItem] = []

    // 1. System items from controlcenter
    if let ccOutput = captureDefaults(["read", "com.apple.controlcenter"]) {
        let lines = ccOutput.components(separatedBy: "\n")
        var visibleMap: [String: Bool] = [:]
        var visibleCCMap: [String: Bool] = [:]
        var posMap: [String: Int] = [:]

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            let parts = t.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces)
            let v = parts[1].trimmingCharacters(in: .init(charactersIn: " ;"))

            if t.contains("NSStatusItem Visible ") && !t.contains("VisibleCC") && !t.contains("Preferred") {
                let name = k.replacingOccurrences(of: "\"NSStatusItem Visible ", with: "").replacingOccurrences(of: "\"", with: "")
                if !name.hasPrefix("Item-") { visibleMap[name] = v == "1" }
            } else if t.contains("NSStatusItem VisibleCC ") {
                let name = k.replacingOccurrences(of: "\"NSStatusItem VisibleCC ", with: "").replacingOccurrences(of: "\"", with: "")
                if !name.contains("-") { visibleCCMap[name] = v == "1" }
            } else if t.contains("NSStatusItem Preferred Position ") {
                let name = k.replacingOccurrences(of: "\"NSStatusItem Preferred Position ", with: "").replacingOccurrences(of: "\"", with: "")
                if !name.contains("-") { posMap[name] = Int(v) }
            }
        }

        for name in Set(knownCCItems).union(visibleMap.keys).union(visibleCCMap.keys) {
            let vis = visibleMap[name] ?? visibleCCMap[name] ?? (posMap[name] != nil)
            items.append(MenuBarItem(name: name, domain: "controlcenter", position: posMap[name], visible: vis))
        }
    }

    // 2. Third-party and other system apps
    for d in domains {
        let d = d.trimmingCharacters(in: .whitespacesAndNewlines)
        if d == "com.apple.controlcenter" { continue }

        guard let output = captureDefaults(["read", d]) else { continue }
        guard output.contains("NSStatusItem") else { continue }

        let lines = output.components(separatedBy: "\n")
        var hasPosition = false
        var position: Int? = nil

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("NSStatusItem Preferred Position") {
                hasPosition = true
                let parts = t.components(separatedBy: "=")
                if parts.count == 2 {
                    position = Int(parts[1].trimmingCharacters(in: .init(charactersIn: " ;")))
                }
            }
        }

        // App has a menu bar presence
        let friendly = bundleNames[d] ?? appNameFromBundle(d)
        items.append(MenuBarItem(name: friendly, domain: d, position: position, visible: hasPosition))
    }

    // Sort: by position (left to right), items without position at the end
    items.sort { a, b in
        if a.visible != b.visible { return a.visible }
        let posA = a.position ?? 9999
        let posB = b.position ?? 9999
        return posA < posB
    }

    if jsonMode {
        let jsonItems = items.map { item -> [String: Any] in
            var dict: [String: Any] = ["name": item.name, "visible": item.visible]
            if let pos = item.position { dict["position"] = pos }
            return dict
        }
        printJSON(["items": jsonItems])
        return
    }

    if items.isEmpty {
        print("No menu bar items found.")
        return
    }

    let maxName = max(items.map { $0.name.count }.max() ?? 10, 20)
    print("Menu bar items:")
    print("")
    for item in items {
        let icon = item.visible ? "[+]" : "[-]"
        let name = item.name.padding(toLength: maxName, withPad: " ", startingAt: 0)
        let pos = item.position.map { "pos: \($0)" } ?? ""
        print("  \(icon) \(name)  \(pos)")
    }
}

private func appNameFromBundle(_ bundleID: String) -> String {
    // Try to get app name from bundle ID
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return url.deletingPathExtension().lastPathComponent
    }
    // Fallback: extract last component of bundle ID
    return bundleID.components(separatedBy: ".").last ?? bundleID
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

private func captureCmd(_ path: String, args: [String], allowFailure: Bool = false) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
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

    if !allowFailure && process.terminationStatus != 0 { return nil }
    return String(data: data, encoding: .utf8)
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
