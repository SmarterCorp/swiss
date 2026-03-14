import Foundation

func runCleanCommand(args: [String]) {
    let action = args.first ?? "run"

    switch action {
    case "run", "--force", "--dry-run":
        ensureMacCleanup()
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
        // Treat as app name for uninstall if not a flag
        if action.hasPrefix("-") {
            fputs("Unknown option: \(action)\n", stderr)
            printCleanUsage()
            exit(1)
        }
        ensureMacCleanup()
        runCleanup(force: false, dryRun: false)
    }
}

private func printCleanUsage() {
    print("Usage: swiss clean [options]")
    print("")
    print("Commands:")
    print("  (no args)           — run cleanup (shows preview, asks to confirm)")
    print("  --dry-run           — show what would be cleaned without deleting")
    print("  --force             — skip confirmation")
    print("  uninstall <app>     — fully uninstall an app with all leftover files")
    print("  help                — show this help")
}

// MARK: - Cleanup

private func ensureMacCleanup() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["which", "mac-cleanup"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fputs("Installing mac-cleanup...\n", stderr)
        let install = Process()
        install.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        install.arguments = ["pip3", "install", "mac-cleanup"]
        try? install.run()
        install.waitUntilExit()

        if install.terminationStatus != 0 {
            fputs("Error: Failed to install mac-cleanup. Try: pip3 install mac-cleanup\n", stderr)
            exit(1)
        }
    }
}

private func runCleanup(force: Bool, dryRun: Bool) {
    if dryRun {
        print("Dry run — showing what would be cleaned:\n")
        execCleanup(["-n"])
    }

    if !force {
        // Show dry run first
        print("Scanning...\n")
        let preview = Process()
        preview.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        preview.arguments = ["mac-cleanup", "-n"]
        try? preview.run()
        preview.waitUntilExit()

        print("")
        fputs("Proceed with cleanup? [y/N] ", stderr)
        guard let answer = readLine(), answer.lowercased() == "y" else {
            print("Cancelled.")
            return
        }
    }

    execCleanup([])
}

private func execCleanup(_ args: [String]) -> Never {
    let argv = (["mac-cleanup"] + args).map { strdup($0) } + [nil]
    execvp("mac-cleanup", argv)
    perror("Failed to exec mac-cleanup")
    exit(1)
}

// MARK: - App Uninstall

private func uninstallApp(_ appName: String) {
    // Find the .app bundle
    let fm = FileManager.default
    let appPath: String

    if appName.hasSuffix(".app") {
        appPath = appName
    } else {
        appPath = "/Applications/\(appName).app"
    }

    guard fm.fileExists(atPath: appPath) else {
        fputs("App not found: \(appPath)\n", stderr)
        fputs("Tip: use the exact app name, e.g. 'swiss clean uninstall Telegram'\n", stderr)
        exit(1)
    }

    // Get bundle identifier
    let plistPath = appPath + "/Contents/Info.plist"
    guard let plist = NSDictionary(contentsOfFile: plistPath),
          let bundleID = plist["CFBundleIdentifier"] as? String else {
        fputs("Could not read bundle identifier from \(appPath)\n", stderr)
        exit(1)
    }

    let appDisplayName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
    print("Uninstalling \(appDisplayName) (\(bundleID))...")
    print("")

    // Find all associated files
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

    // Also search for any plist files matching the bundle ID pattern
    let prefsDir = NSHomeDirectory() + "/Library/Preferences"
    if let prefs = try? fm.contentsOfDirectory(atPath: prefsDir) {
        for file in prefs where file.contains(bundleID) {
            filesToRemove.append(prefsDir + "/\(file)")
        }
    }

    // Show what will be removed
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

    // Remove files
    for path in filesToRemove {
        do {
            try fm.removeItem(atPath: path)
        } catch {
            fputs("  Failed to remove: \(path)\n", stderr)
        }
    }

    print("\(appDisplayName) uninstalled.")
}

private func fileSize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var total: Int64 = 0

    if let attrs = try? fm.attributesOfItem(atPath: path) {
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            if let enumerator = fm.enumerator(atPath: path) {
                while let file = enumerator.nextObject() as? String {
                    let fullPath = path + "/\(file)"
                    if let fileAttrs = try? fm.attributesOfItem(atPath: fullPath),
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
