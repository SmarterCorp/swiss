import Foundation
import IOKit.ps
import CoreWLAN
import CoreGraphics

private let boxWidth = 56

func runDashCommand() {
    printBox("System", dashSystem())
    printBox("Services", dashServices())
    printBox("Feeds", dashFeeds())
    printBox("Network", dashNetwork())
}

// MARK: - System

private func dashSystem() -> [String] {
    var lines: [String] = []

    // Battery
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
    if let source = sources.first {
        let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as! [String: Any]
        let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let pct = max > 0 ? capacity * 100 / max : 0
        let charging = (desc[kIOPSIsChargingKey] as? Bool) == true
        let filled = pct / 10
        let bar = String(repeating: "#", count: filled) + String(repeating: ".", count: 10 - filled)
        let status = charging ? "charging" : "on battery"
        lines.append(dashRow("Battery", "\(pct)% [\(bar)] \(status)"))
    }

    // Network connection — CWWiFiClient hides SSID on macOS 15+ without Location Services
    // Use system_profiler as reliable fallback
    if let airportInfo = dashCapture("/bin/sh", args: ["-c", "system_profiler SPAirPortDataType 2>/dev/null | grep -A10 'Current Network Information:' | head -12"]),
       airportInfo.contains("Status: Connected") || airportInfo.contains("PHY Mode") {
        // Extract signal strength
        var signal = ""
        var quality = ""
        for line in airportInfo.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Signal / Noise:") {
                let parts = trimmed.replacingOccurrences(of: "Signal / Noise:", with: "").trimmingCharacters(in: .whitespaces)
                if let dbm = parts.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) {
                    signal = dbm
                    let val = Int(dbm.replacingOccurrences(of: " dBm", with: "")) ?? -100
                    switch val {
                    case -50...0: quality = "Excellent"
                    case -60 ..< -50: quality = "Good"
                    case -70 ..< -60: quality = "Fair"
                    default: quality = "Weak"
                    }
                }
            }
        }
        // Try to get SSID from CWWiFiClient first
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        if let ssid = ssid {
            lines.append(dashRow("Network", "WiFi: \(ssid) \(signal) (\(quality))"))
        } else if !signal.isEmpty {
            lines.append(dashRow("Network", "WiFi: \(signal) (\(quality))"))
        } else {
            lines.append(dashRow("Network", "WiFi: connected"))
        }
    } else if let ip = dashCapture("/usr/sbin/ipconfig", args: ["getifaddr", "en0"]), !ip.isEmpty {
        let activePort = dashCapture("/bin/sh", args: ["-c", "route -n get default 2>/dev/null | awk '/interface:/{print $2}'"]) ?? "en0"
        lines.append(dashRow("Network", "Ethernet (\(activePort))"))
    } else {
        lines.append(dashRow("Network", "disconnected"))
    }

    // Displays
    var displayCount: UInt32 = 0
    CGGetOnlineDisplayList(10, nil, &displayCount)
    let external = displayCount > 1 ? Int(displayCount) - 1 : 0
    lines.append(dashRow("Displays", "\(external) external"))

    // Trash
    let fm = FileManager.default
    if let trashURL = fm.urls(for: .trashDirectory, in: .userDomainMask).first,
       let items = try? fm.contentsOfDirectory(atPath: trashURL.path) {
        let count = items.filter { !$0.hasPrefix(".") }.count
        lines.append(dashRow("Trash", "\(count) items"))
    }

    // Disk
    if let attrs = try? fm.attributesOfFileSystem(forPath: "/"),
       let free = attrs[.systemFreeSize] as? Int64,
       let total = attrs[.systemSize] as? Int64 {
        let freeGB = free / (1024 * 1024 * 1024)
        let totalGB = total / (1024 * 1024 * 1024)
        lines.append(dashRow("Disk", "\(freeGB) GB free / \(totalGB) GB"))
    }

    // Sleep
    if let pmOutput = dashCapture("/usr/bin/pmset", args: ["-g"]) {
        let sleepDisabled = pmOutput.contains("disablesleep\t\t1") || pmOutput.contains("disablesleep             1")
        lines.append(dashRow("Sleep", sleepDisabled ? "DISABLED (awake)" : "enabled"))
    }

    return lines
}

// MARK: - Services

private func dashServices() -> [String] {
    let services: [(String, Bool)] = [
        ("espanso", dashCheckProcess("espanso", args: ["status"], expect: "running")),
        ("ollama", dashCheckHTTP(port: "11434")),
        ("docker", dashCheckSilent("/usr/bin/env", args: ["docker", "info"])),
        ("cursor", dashCheckPID(NSString("~/.swiss-cursor.pid").expandingTildeInPath)),
        ("rsshub", dashCheckContainer("rsshub")),
        ("pipit", dashCheckSilent("/usr/bin/pgrep", args: ["-x", "Pipit"])),
    ]

    // Layout in 3 columns
    var rows: [String] = []
    let perRow = 3
    for i in stride(from: 0, to: services.count, by: perRow) {
        let chunk = services[i..<min(i + perRow, services.count)]
        let cols = chunk.map { name, running -> String in
            let icon = running ? "+" : "-"
            return "[\(icon)] \(name)".padding(toLength: 15, withPad: " ", startingAt: 0)
        }
        rows.append(cols.joined(separator: " "))
    }
    return rows
}

// MARK: - Feeds

private func dashFeeds() -> [String] {
    var lines: [String] = []

    // RSS feeds
    let urlsFile = NSHomeDirectory() + "/.newsboat/urls"
    if let content = try? String(contentsOfFile: urlsFile, encoding: .utf8) {
        let feeds = content.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let twitterFeeds = feeds.filter { $0.contains("twitter") || $0.contains("rsshub") }
        let rssFeeds = feeds.count - twitterFeeds.count
        lines.append(dashRow("RSS", "\(rssFeeds) feeds"))
        if !twitterFeeds.isEmpty {
            let accounts = twitterFeeds.compactMap { line -> String? in
                if let start = line.range(of: "\"~@"), let end = line.range(of: "\"", range: line.index(start.upperBound, offsetBy: 0)..<line.endIndex) {
                    return "@" + String(line[start.upperBound..<end.lowerBound])
                }
                return nil
            }
            let preview = accounts.prefix(3).joined(separator: ", ")
            lines.append(dashRow("Twitter", "\(twitterFeeds.count) accounts (\(preview))"))
        }
    }

    // Prompts
    let swissYml = NSHomeDirectory() + "/Library/Application Support/espanso/match/swiss.yml"
    if let content = try? String(contentsOfFile: swissYml, encoding: .utf8) {
        let count = content.components(separatedBy: "- trigger:").count - 1
        lines.append(dashRow("Prompts", "\(count) expansions"))
    } else {
        lines.append(dashRow("Prompts", "0 expansions"))
    }

    return lines
}

// MARK: - Network

private func dashNetwork() -> [String] {
    var lines: [String] = []

    // Local IP
    if let output = dashCapture("/usr/sbin/ipconfig", args: ["getifaddr", "en0"]) {
        lines.append(dashRow("IP", output))
    } else {
        lines.append(dashRow("IP", "N/A"))
    }

    // Listening ports
    if let output = dashCapture("/usr/sbin/lsof", args: ["-iTCP", "-sTCP:LISTEN", "-nP", "-Fn"]) {
        let ports = Set(output.components(separatedBy: "\n")
            .filter { $0.hasPrefix("n") && $0.contains(":") }
            .compactMap { line -> String? in
                line.components(separatedBy: ":").last
            })
        let sorted = ports.compactMap { Int($0) }.sorted().prefix(4)
        let portList = sorted.map(String.init).joined(separator: ", ")
        lines.append(dashRow("Ports", "\(ports.count) listening (\(portList))"))
    }

    return lines
}

// MARK: - Box drawing

private func printBox(_ title: String, _ lines: [String]) {
    let inner = boxWidth - 4
    let titleBar = " \(title) ".padding(toLength: inner, withPad: "\u{2500}", startingAt: 0)
    print("\u{256D}\u{2500}\(titleBar)\u{2500}\u{256E}")
    for line in lines {
        let trimmed = line.count > inner ? String(line.prefix(inner)) : line
        let padded = trimmed.padding(toLength: inner, withPad: " ", startingAt: 0)
        print("\u{2502} \(padded) \u{2502}")
    }
    print("\u{2570}" + String(repeating: "\u{2500}", count: inner + 2) + "\u{256F}")
}

private func dashRow(_ label: String, _ value: String) -> String {
    let paddedLabel = label.padding(toLength: 10, withPad: " ", startingAt: 0)
    return "\(paddedLabel)\(value)"
}

// MARK: - Check helpers

private func dashCheckProcess(_ binary: String, args: [String], expect: String) -> Bool {
    guard let output = dashCapture("/usr/bin/env", args: [binary] + args) else { return false }
    return output.contains(expect)
}

private func dashCheckHTTP(port: String) -> Bool {
    guard let code = dashCapture("/usr/bin/curl", args: ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "1", "http://localhost:\(port)/"]) else { return false }
    return code == "200" || code == "301" || code == "302"
}

private func dashCheckSilent(_ path: String, args: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func dashCheckPID(_ pidFile: String) -> Bool {
    guard let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(pidStr) else { return false }
    return kill(pid, 0) == 0
}

private func dashCheckContainer(_ name: String) -> Bool {
    guard let output = dashCapture("/usr/bin/env", args: ["docker", "inspect", "--format", "{{.State.Running}}", name]) else { return false }
    return output == "true"
}

private func dashCapture(_ path: String, args: [String]) -> String? {
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

    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
