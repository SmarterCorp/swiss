import Foundation

struct CLIBridge {
    static let swissPath = "/usr/local/bin/swiss"

    static func run(_ args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: swissPath)
                process.arguments = args
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                try? process.run()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    // MARK: - Parsed outputs

    struct ServiceInfo {
        let name: String
        let running: Bool
    }

    struct SystemInfo {
        let battery: String
        let network: String
        let displays: String
        let disk: String
        let sleep: String
    }

    static func dashboard() async -> (system: SystemInfo, services: [ServiceInfo], feeds: [String], network: [String]) {
        let output = await run(["dash"])
        let lines = output.components(separatedBy: "\n")

        var system = SystemInfo(battery: "N/A", network: "N/A", displays: "N/A", disk: "N/A", sleep: "N/A")
        var services: [ServiceInfo] = []
        var feeds: [String] = []
        var networkLines: [String] = []

        enum Section { case none, system, services, feeds, network }
        var section: Section = .none

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.contains("System") && t.contains("\u{2500}") { section = .system; continue }
            if t.contains("Services") && t.contains("\u{2500}") { section = .services; continue }
            if t.contains("Feeds") && t.contains("\u{2500}") { section = .feeds; continue }
            if t.contains("Network") && t.contains("\u{2500}") { section = .network; continue }
            if t.hasPrefix("\u{2570}") || t.hasPrefix("\u{256E}") { continue } // box borders

            let clean = t.replacingOccurrences(of: "\u{2502}", with: "").trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }

            switch section {
            case .system:
                if clean.hasPrefix("Battery") { system = SystemInfo(battery: extractValue(clean), network: system.network, displays: system.displays, disk: system.disk, sleep: system.sleep) }
                if clean.hasPrefix("Network") { system = SystemInfo(battery: system.battery, network: extractValue(clean), displays: system.displays, disk: system.disk, sleep: system.sleep) }
                if clean.hasPrefix("Displays") { system = SystemInfo(battery: system.battery, network: system.network, displays: extractValue(clean), disk: system.disk, sleep: system.sleep) }
                if clean.hasPrefix("Disk") { system = SystemInfo(battery: system.battery, network: system.network, displays: system.displays, disk: extractValue(clean), sleep: system.sleep) }
                if clean.hasPrefix("Sleep") { system = SystemInfo(battery: system.battery, network: system.network, displays: system.displays, disk: system.disk, sleep: extractValue(clean)) }
            case .services:
                // Parse "[+] name" patterns
                let parts = clean.components(separatedBy: "  ").filter { !$0.isEmpty }
                for part in parts {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("[+]") {
                        services.append(ServiceInfo(name: trimmed.replacingOccurrences(of: "[+] ", with: ""), running: true))
                    } else if trimmed.hasPrefix("[-]") {
                        services.append(ServiceInfo(name: trimmed.replacingOccurrences(of: "[-] ", with: ""), running: false))
                    }
                }
            case .feeds:
                feeds.append(clean)
            case .network:
                networkLines.append(clean)
            case .none:
                break
            }
        }

        return (system: system, services: services, feeds: feeds, network: networkLines)
    }

    private static func extractValue(_ line: String) -> String {
        let parts = line.components(separatedBy: "  ").filter { !$0.isEmpty }
        return parts.count > 1 ? parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces) : ""
    }
}
