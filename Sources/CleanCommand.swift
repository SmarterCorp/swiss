import Foundation

private let cleanTargets: [(name: String, paths: [String])] = [
    ("System caches", ["~/Library/Caches/*"]),
    ("System logs", ["~/Library/Logs/*"]),
    ("User temp files", ["/tmp/*"]),
    ("Xcode DerivedData", ["~/Library/Developer/Xcode/DerivedData/*"]),
    ("Xcode Archives", ["~/Library/Developer/Xcode/Archives/*"]),
    ("Xcode device support", ["~/Library/Developer/Xcode/iOS DeviceSupport/*"]),
    ("Homebrew cache", ["~/Library/Caches/Homebrew/*"]),
    ("npm cache", ["~/.npm/_cacache/*"]),
    ("yarn cache", ["~/Library/Caches/Yarn/*"]),
    ("pip cache", ["~/Library/Caches/pip/*"]),
    ("Docker unused", []),  // special: handled via docker system prune
    ("Trash", []),          // special: handled via Finder API
    (".DS_Store files", []),  // special: find and delete
]

func runCleanCommand(args: [String]) {
    let action = args.first ?? "run"

    switch action {
    case "run", "--force", "--dry-run":
        let force = args.contains("--force")
        let dryRun = args.contains("--dry-run")
        runCleanup(force: force, dryRun: dryRun)

    case "uninstall":
        guard args.count >= 2 else {
            fputs("Usage: swiss clean uninstall <app-name>\n", stderr)
            exit(1)
        }
        let appName = args.dropFirst().joined(separator: " ")
        uninstallApp(appName)

    case "help", "-h", "--help":
        printCleanUsage()

    default:
        if action.hasPrefix("-") {
            fputs("Unknown option: \(action)\n", stderr)
            printCleanUsage()
            exit(1)
        }
        runCleanup(force: false, dryRun: false)
    }
}

private func printCleanUsage() {
    print("Usage: swiss clean [options]")
    print("")
    print("Commands:")
    print("  (no args)           — scan and clean (with confirmation)")
    print("  --dry-run           — show what would be cleaned")
    print("  --force             — skip confirmation")
    print("  uninstall <app>     — fully uninstall an app with all leftovers")
}

// MARK: - Cleanup

private func runCleanup(force: Bool, dryRun: Bool) {
    let fm = FileManager.default
    var totalSize: Int64 = 0
    var results: [(name: String, size: Int64, paths: [String])] = []

    print("Scanning...\n")

    for target in cleanTargets {
        if target.name == "Docker unused" || target.name == "Trash" || target.name == ".DS_Store files" {
            continue // handle separately
        }

        var targetSize: Int64 = 0
        var expandedPaths: [String] = []

        for pattern in target.paths {
            let expanded = (pattern as NSString).expandingTildeInPath
            let dir = (expanded as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: dir) else { continue }

            if let items = try? fm.contentsOfDirectory(atPath: dir) {
                for item in items {
                    let fullPath = dir + "/\(item)"
                    let size = fileSize(fullPath)
                    if size > 0 {
                        targetSize += size
                        expandedPaths.append(fullPath)
                    }
                }
            }
        }

        if targetSize > 0 {
            results.append((name: target.name, size: targetSize, paths: expandedPaths))
            totalSize += targetSize
        }
    }

    // Trash size
    if let trashURL = fm.urls(for: .trashDirectory, in: .userDomainMask).first {
        let trashSize = fileSize(trashURL.path)
        if trashSize > 0 {
            results.append((name: "Trash", size: trashSize, paths: [trashURL.path]))
            totalSize += trashSize
        }
    }

    // Homebrew cleanup (estimate)
    if let brewOutput = captureProcess("/usr/bin/env", args: ["brew", "cleanup", "-n"]) {
        let lines = brewOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        if !lines.isEmpty {
            results.append((name: "Homebrew outdated (\(lines.count) items)", size: 0, paths: []))
        }
    }

    // Print results
    if results.isEmpty {
        print("System is clean.")
        return
    }

    let maxName = max(results.map { $0.name.count }.max() ?? 20, 20)
    for result in results {
        let name = result.name.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
        let size = result.size > 0 ? formatSize(result.size) : "cleanup available"
        print("  \(name) \(size)")
    }
    print("")
    print("  Total: \(formatSize(totalSize))")
    print("")

    if dryRun {
        print("(dry run — nothing deleted)")
        return
    }

    if !force {
        fputs("Clean all? [y/N] ", stderr)
        guard let answer = readLine(), answer.lowercased() == "y" else {
            print("Cancelled.")
            return
        }
    }

    // Execute cleanup
    print("")
    for result in results {
        if result.name == "Trash" {
            fputs("Emptying Trash...\n", stderr)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["rm", "-rf"]
            if let trashURL = fm.urls(for: .trashDirectory, in: .userDomainMask).first,
               let items = try? fm.contentsOfDirectory(atPath: trashURL.path) {
                process.arguments! += items.map { trashURL.path + "/\($0)" }
                try? process.run()
                process.waitUntilExit()
            }
        } else if result.name.hasPrefix("Homebrew") {
            fputs("Running brew cleanup...\n", stderr)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["brew", "cleanup"]
            try? process.run()
            process.waitUntilExit()
        } else {
            fputs("Cleaning \(result.name)...\n", stderr)
            for path in result.paths {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    print("")
    print("Cleaned \(formatSize(totalSize)).")
}

// MARK: - App Uninstall

private func uninstallApp(_ appName: String) {
    // Sanitize: strip path separators to prevent traversal
    let sanitized = appName.components(separatedBy: "/").last ?? appName
    let fm = FileManager.default
    let appPath: String

    if sanitized.hasSuffix(".app") {
        appPath = "/Applications/\(sanitized)"
    } else {
        appPath = "/Applications/\(sanitized).app"
    }

    guard fm.fileExists(atPath: appPath) else {
        fputs("App not found: \(appPath)\n", stderr)
        fputs("Tip: use the exact app name, e.g. 'swiss clean uninstall Telegram'\n", stderr)
        exit(1)
    }

    let plistPath = appPath + "/Contents/Info.plist"
    guard let plist = NSDictionary(contentsOfFile: plistPath),
          let bundleID = plist["CFBundleIdentifier"] as? String else {
        fputs("Could not read bundle identifier from \(appPath)\n", stderr)
        exit(1)
    }

    let appDisplayName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    print("Uninstalling \(appDisplayName) (\(bundleID))...\n")

    let searchPaths = [
        NSHomeDirectory() + "/Library/Application Support/\(bundleID)",
        NSHomeDirectory() + "/Library/Application Support/\(appDisplayName)",
        NSHomeDirectory() + "/Library/Caches/\(bundleID)",
        NSHomeDirectory() + "/Library/Caches/\(appDisplayName)",
        NSHomeDirectory() + "/Library/Preferences/\(bundleID).plist",
        NSHomeDirectory() + "/Library/Logs/\(bundleID)",
        NSHomeDirectory() + "/Library/Logs/\(appDisplayName)",
        NSHomeDirectory() + "/Library/Containers/\(bundleID)",
        NSHomeDirectory() + "/Library/Group Containers/\(bundleID)",
        NSHomeDirectory() + "/Library/Saved Application State/\(bundleID).savedState",
        NSHomeDirectory() + "/Library/WebKit/\(bundleID)",
        NSHomeDirectory() + "/Library/HTTPStorages/\(bundleID)",
    ]

    var filesToRemove: [String] = [appPath]
    for path in searchPaths {
        if fm.fileExists(atPath: path) {
            filesToRemove.append(path)
        }
    }

    let prefsDir = NSHomeDirectory() + "/Library/Preferences"
    if let prefs = try? fm.contentsOfDirectory(atPath: prefsDir) {
        for file in prefs where file.contains(bundleID) && !filesToRemove.contains(prefsDir + "/\(file)") {
            filesToRemove.append(prefsDir + "/\(file)")
        }
    }

    print("Files to remove:")
    var totalSize: Int64 = 0
    for path in filesToRemove {
        let size = fileSize(path)
        totalSize += size
        let sizeStr = formatSize(size)
        let shortPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        print("  \(sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(shortPath)")
    }
    print("")
    print("Total: \(formatSize(totalSize))")
    print("")

    fputs("Remove all? [y/N] ", stderr)
    guard let answer = readLine(), answer.lowercased() == "y" else {
        print("Cancelled.")
        return
    }

    for path in filesToRemove {
        do {
            try fm.removeItem(atPath: path)
        } catch {
            fputs("  Failed to remove: \(path)\n", stderr)
        }
    }

    print("\(appDisplayName) uninstalled.")
}

// MARK: - Helpers

private func fileSize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var total: Int64 = 0

    if let attrs = try? fm.attributesOfItem(atPath: path) {
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            if let enumerator = fm.enumerator(atPath: path) {
                while let file = enumerator.nextObject() as? String {
                    if let fileAttrs = try? fm.attributesOfItem(atPath: path + "/\(file)"),
                       let size = fileAttrs[.size] as? Int64 {
                        total += size
                    }
                }
            }
        } else if let size = attrs[.size] as? Int64 {
            total = size
        }
    }
    return total
}

private func formatSize(_ bytes: Int64) -> String {
    if bytes >= 1_073_741_824 {
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    } else if bytes >= 1_048_576 {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    } else if bytes >= 1024 {
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
    return "\(bytes) B"
}

private func captureProcess(_ path: String, args: [String]) -> String? {
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
    return String(data: data, encoding: .utf8)
}
