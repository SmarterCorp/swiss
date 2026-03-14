import AppKit

// MARK: - Types

private enum CleanRisk: Int, Comparable {
    case safe = 0        // auto-regenerated, no data loss
    case moderate = 1    // useful data may be lost (logs, debug info)
    case caution = 2     // may contain important data (archives, builds)

    static func < (lhs: CleanRisk, rhs: CleanRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .safe:     return "safe"
        case .moderate: return "moderate"
        case .caution:  return "caution"
        }
    }
}

private struct CleanResult {
    let name: String
    let size: Int64
    let paths: [String]
    let risk: CleanRisk
}

private let maxProcessOutput = 10 * 1024 * 1024 // 10 MB
private let maxFileEnumeration = 500_000

private let cleanTargets: [(name: String, paths: [String], risk: CleanRisk)] = [
    ("System caches", ["~/Library/Caches/*"], .safe),
    ("System logs", ["~/Library/Logs/*"], .moderate),
    ("User temp files", [], .safe),          // special: uses NSTemporaryDirectory()
    ("Xcode DerivedData", ["~/Library/Developer/Xcode/DerivedData/*"], .safe),
    ("Xcode Archives", ["~/Library/Developer/Xcode/Archives/*"], .caution),
    ("Xcode device support", ["~/Library/Developer/Xcode/iOS DeviceSupport/*"], .moderate),
    ("Homebrew cache", ["~/Library/Caches/Homebrew/*"], .safe),
    ("npm cache", ["~/.npm/_cacache/*"], .safe),
    ("yarn cache", ["~/Library/Caches/Yarn/*"], .safe),
    ("pip cache", ["~/Library/Caches/pip/*"], .safe),
    ("Trash", [], .safe),              // special: handled via scanTrash()
]

// MARK: - Entry Point

func runCleanCommand(args: [String]) {
    let action = args.first ?? "run"

    let force = args.contains("--force")
    let dryRun = args.contains("--dry-run")

    let maxRisk: CleanRisk
    if args.contains("--all") || args.contains("--caution") {
        maxRisk = .caution
    } else if args.contains("--moderate") {
        maxRisk = .moderate
    } else {
        maxRisk = .safe
    }

    switch action {
    case "run", "--force", "--dry-run", "--safe", "--moderate", "--caution", "--all":
        runCleanup(force: force, dryRun: dryRun, maxRisk: maxRisk)

    case "uninstall":
        let appArgs = args.dropFirst().filter { !$0.hasPrefix("-") }
        guard !appArgs.isEmpty else {
            fputs("Usage: swiss clean uninstall <app-name>\n", stderr)
            exit(1)
        }
        let appName = appArgs.joined(separator: " ")
        uninstallApp(appName)

    case "help", "-h", "--help":
        printCleanUsage()

    default:
        fputs("Unknown argument: \(action)\n", stderr)
        printCleanUsage()
        exit(1)
    }
}

private func printCleanUsage() {
    print("Usage: swiss clean [options]")
    print("")
    print("Commands:")
    print("  (no args)           — scan and clean (with confirmation)")
    print("  --dry-run           — show what would be cleaned")
    print("  --force             — skip confirmation")
    print("  --safe              — only safe items (default)")
    print("  --moderate          — safe + moderate items")
    print("  --caution           — safe + moderate + caution items")
    print("  --all               — alias for --caution")
    print("  uninstall <app>     — fully uninstall an app with all leftovers")
}

// MARK: - Cleanup

private func runCleanup(force: Bool, dryRun: Bool, maxRisk: CleanRisk = .safe) {
    var results = scanCleanTargets()
    results += scanTrash()
    results += scanHomebrew()

    if results.isEmpty {
        print("System is clean.")
        return
    }

    let totalSize = results.reduce(Int64(0)) { $0 + $1.size }

    if jsonMode {
        let jsonResults = results.map { ["name": $0.name, "size_bytes": $0.size] as [String: Any] }
        printJSON(["results": jsonResults, "total_bytes": totalSize, "dry_run": dryRun])
        return
    }

    printCleanResults(results, totalSize: totalSize)

    if dryRun {
        print("(dry run — nothing deleted)")
        return
    }

    let toClean = results.filter { $0.risk <= maxRisk }
    if toClean.isEmpty {
        print("Nothing to clean at level: \(maxRisk.label).")
        return
    }

    let cleanSize = toClean.reduce(Int64(0)) { $0 + $1.size }
    let levelLabel = maxRisk == .caution ? "all" : maxRisk.label

    if !force {
        fputs("Clean \(formatSize(cleanSize)) (level: \(levelLabel))? [y/N] ", stderr)
        guard let answer = readLine(), answer.lowercased() == "y" else {
            print("Cancelled.")
            return
        }
    }

    executeCleanup(toClean)
    print("")
    print("Cleaned \(formatSize(cleanSize)).")
}

private func scanCleanTargets() -> [CleanResult] {
    let fm = FileManager.default
    var results: [CleanResult] = []
    let home = NSHomeDirectory()

    print("Scanning...\n")

    for target in cleanTargets {
        if target.paths.isEmpty && target.name != "User temp files" { continue }

        var targetSize: Int64 = 0
        var expandedPaths: [String] = []
        var itemCount = 0

        for pattern in target.paths {
            scanDirectory(pattern: pattern, home: home, fm: fm, itemCount: &itemCount,
                          targetSize: &targetSize, expandedPaths: &expandedPaths)
        }

        if target.name == "User temp files" {
            scanTempDirectory(fm: fm, itemCount: &itemCount,
                              targetSize: &targetSize, expandedPaths: &expandedPaths)
        }

        if targetSize > 0 {
            results.append(CleanResult(name: target.name, size: targetSize, paths: expandedPaths, risk: target.risk))
        }
    }
    return results
}

private func scanDirectory(pattern: String, home: String, fm: FileManager,
                           itemCount: inout Int, targetSize: inout Int64,
                           expandedPaths: inout [String]) {
    let expanded = (pattern as NSString).expandingTildeInPath
    let dir = (expanded as NSString).deletingLastPathComponent

    // Validate against home directory, not self-referentially
    guard let resolvedDir = resolveAndValidatePath(dir, allowedParent: home),
          fm.fileExists(atPath: resolvedDir) else { return }

    guard let items = try? fm.contentsOfDirectory(atPath: resolvedDir) else { return }
    for item in items {
        itemCount += 1
        if itemCount > maxFileEnumeration { break }
        let fullPath = resolvedDir + "/\(item)"
        guard resolveAndValidatePath(fullPath, allowedParent: resolvedDir) != nil else { continue }
        let size = fileSize(fullPath)
        if size > 0 {
            targetSize += size
            expandedPaths.append(fullPath)
        }
    }
}

private func scanTempDirectory(fm: FileManager, itemCount: inout Int,
                               targetSize: inout Int64, expandedPaths: inout [String]) {
    var tmpDir = NSTemporaryDirectory()
    if !tmpDir.hasSuffix("/") { tmpDir += "/" }

    guard let items = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
    for item in items {
        itemCount += 1
        if itemCount > maxFileEnumeration { break }
        let fullPath = tmpDir + item
        guard resolveAndValidatePath(fullPath, allowedParent: tmpDir) != nil else { continue }
        let size = fileSize(fullPath)
        if size > 0 {
            targetSize += size
            expandedPaths.append(fullPath)
        }
    }
}

private func scanTrash() -> [CleanResult] {
    let fm = FileManager.default
    if let trashURL = fm.urls(for: .trashDirectory, in: .userDomainMask).first {
        let trashSize = fileSize(trashURL.path)
        if trashSize > 0 {
            return [CleanResult(name: "Trash", size: trashSize, paths: [trashURL.path], risk: .safe)]
        }
    }
    return []
}

private func scanHomebrew() -> [CleanResult] {
    if let brewOutput = captureProcess("/usr/bin/env", args: ["brew", "cleanup", "-n"]) {
        let lines = brewOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        if !lines.isEmpty {
            return [CleanResult(name: "Homebrew outdated (\(lines.count) items)", size: 0, paths: [], risk: .safe)]
        }
    }
    return []
}

private func printCleanResults(_ results: [CleanResult], totalSize: Int64) {
    let maxName = max(results.map { $0.name.count }.max() ?? 20, 20)
    for result in results {
        let name = result.name.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
        let size = result.size > 0 ? formatSize(result.size) : "cleanup available"
        let riskLabel: String
        switch result.risk {
        case .safe:     riskLabel = "[\u{2713} safe]"
        case .moderate: riskLabel = "[~ moderate]"
        case .caution:  riskLabel = "[! caution]"
        }
        let sizeStr = size.padding(toLength: 18, withPad: " ", startingAt: 0)
        print("  \(name) \(sizeStr) \(riskLabel)")
    }
    print("")
    print("  Total: \(formatSize(totalSize))")
    print("")
}

private func executeCleanup(_ toClean: [CleanResult]) {
    let fm = FileManager.default
    print("")
    for result in toClean {
        if result.name == "Trash" {
            emptyTrash()
        } else if result.name.hasPrefix("Homebrew") {
            fputs("Running brew cleanup...\n", stderr)
            runProcess("/usr/bin/env", args: ["brew", "cleanup"])
        } else {
            fputs("Cleaning \(result.name)...\n", stderr)
            for path in result.paths {
                // Re-resolve symlinks at deletion time to prevent TOCTOU
                let resolved = (path as NSString).resolvingSymlinksInPath
                guard resolved.hasPrefix(NSHomeDirectory()) || resolved.hasPrefix(NSTemporaryDirectory()) else {
                    fputs("  Skipping (resolved outside allowed scope): \(path)\n", stderr)
                    continue
                }
                do {
                    try fm.removeItem(atPath: resolved)
                } catch {
                    fputs("  Failed to remove: \(path) — \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }
}

private func emptyTrash() {
    let fm = FileManager.default
    fputs("Emptying Trash...\n", stderr)
    guard let trashURL = fm.urls(for: .trashDirectory, in: .userDomainMask).first,
          let items = try? fm.contentsOfDirectory(atPath: trashURL.path) else { return }

    let trashPath = trashURL.path
    for item in items {
        let itemPath = trashPath + "/\(item)"
        // Re-resolve at deletion time to prevent TOCTOU
        guard let resolved = resolveAndValidatePath(itemPath, allowedParent: trashPath) else { continue }
        do {
            try fm.removeItem(atPath: resolved)
        } catch {
            fputs("  Failed to remove trash item: \(item) — \(error.localizedDescription)\n", stderr)
        }
    }
}

// MARK: - App Uninstall

private func uninstallApp(_ appName: String) {
    let appPath = resolveAppPath(appName)
    let (bundleID, appDisplayName) = readAppMetadata(appPath)

    let filesToRemove = discoverAppFiles(appPath: appPath, bundleID: bundleID, displayName: appDisplayName)

    if jsonMode {
        let home = NSHomeDirectory()
        let jsonFiles = filesToRemove.map { path -> [String: Any] in
            ["path": path.replacingOccurrences(of: home, with: "~"), "size_bytes": fileSize(path)]
        }
        let total = filesToRemove.reduce(Int64(0)) { $0 + fileSize($1) }
        printJSON(["app": appDisplayName, "bundle_id": bundleID, "files": jsonFiles, "total_bytes": total])
        return
    }

    terminateIfRunning(bundleID: bundleID, displayName: appDisplayName)
    print("Uninstalling \(appDisplayName) (\(bundleID))...\n")

    printUninstallList(filesToRemove)
    confirmAndRemove(filesToRemove, displayName: appDisplayName)
}

private func resolveAppPath(_ appName: String) -> String {
    // Strict validation: only allow alphanumeric, spaces, hyphens, periods
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -."))
    guard appName.unicodeScalars.allSatisfy({ allowed.contains($0) }),
          !appName.contains(".."),
          !appName.isEmpty else {
        fputs("Invalid app name: \(appName)\n", stderr)
        fputs("Only letters, numbers, spaces, hyphens, and periods are allowed.\n", stderr)
        exit(1)
    }

    let fm = FileManager.default
    let name = appName.hasSuffix(".app") ? appName : "\(appName).app"
    let appPath = "/Applications/\(name)"

    // Resolve symlinks and verify it's a direct child of /Applications
    let resolved = (appPath as NSString).resolvingSymlinksInPath
    guard resolved.hasPrefix("/Applications/"),
          URL(fileURLWithPath: resolved).pathComponents.count == 3 else {
        fputs("App path resolved outside /Applications: \(resolved)\n", stderr)
        exit(1)
    }

    guard fm.fileExists(atPath: resolved) else {
        fputs("App not found: \(appPath)\n", stderr)
        fputs("Tip: use the exact app name, e.g. 'swiss clean uninstall Telegram'\n", stderr)
        exit(1)
    }

    return resolved
}

private func readAppMetadata(_ appPath: String) -> (bundleID: String, displayName: String) {
    let plistPath = appPath + "/Contents/Info.plist"
    guard let plist = NSDictionary(contentsOfFile: plistPath),
          let bundleID = plist["CFBundleIdentifier"] as? String else {
        fputs("Could not read bundle identifier from \(appPath)\n", stderr)
        exit(1)
    }

    // Validate bundleID format: reverse-DNS, only alphanumeric, dots, hyphens
    let bundleAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
    guard bundleID.unicodeScalars.allSatisfy({ bundleAllowed.contains($0) }),
          !bundleID.isEmpty else {
        fputs("Suspicious bundle identifier: \(bundleID)\n", stderr)
        exit(1)
    }

    let displayName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

    // Re-validate displayName (derived from filesystem, not user input)
    let nameAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -."))
    guard displayName.unicodeScalars.allSatisfy({ nameAllowed.contains($0) }),
          !displayName.contains(".."),
          !displayName.isEmpty else {
        fputs("Suspicious app display name: \(displayName)\n", stderr)
        exit(1)
    }

    return (bundleID, displayName)
}

private func terminateIfRunning(bundleID: String, displayName: String) {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
    guard !apps.isEmpty else { return }

    fputs("Stopping \(displayName)...\n", stderr)
    for app in apps {
        app.terminate()
    }

    // Wait up to 3 seconds for graceful termination
    for _ in 0..<6 {
        Thread.sleep(forTimeInterval: 0.5)
        let still = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        if still.isEmpty { return }
    }

    // Force kill if still running
    let remaining = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
    for app in remaining {
        app.forceTerminate()
    }
    Thread.sleep(forTimeInterval: 0.5)
}

private func discoverAppFiles(appPath: String, bundleID: String, displayName: String) -> [String] {
    let fm = FileManager.default
    let home = NSHomeDirectory()

    let searchPaths = [
        "\(home)/Library/Application Support/\(bundleID)",
        "\(home)/Library/Application Support/\(displayName)",
        "\(home)/Library/Caches/\(bundleID)",
        "\(home)/Library/Caches/\(displayName)",
        "\(home)/Library/Preferences/\(bundleID).plist",
        "\(home)/Library/Logs/\(bundleID)",
        "\(home)/Library/Logs/\(displayName)",
        "\(home)/Library/Containers/\(bundleID)",
        "\(home)/Library/Group Containers/\(bundleID)",
        "\(home)/Library/Saved Application State/\(bundleID).savedState",
        "\(home)/Library/WebKit/\(bundleID)",
        "\(home)/Library/HTTPStorages/\(bundleID)",
    ]

    let libraryDir = "\(home)/Library"
    var filesToRemove: [String] = [appPath]
    for path in searchPaths where fm.fileExists(atPath: path) {
        guard resolveAndValidatePath(path, allowedParent: libraryDir) != nil else { continue }
        filesToRemove.append(path)
    }

    let prefsDir = "\(home)/Library/Preferences"
    if let prefs = try? fm.contentsOfDirectory(atPath: prefsDir) {
        for (index, file) in prefs.enumerated() {
            if index > maxFileEnumeration { break }
            guard file.contains(bundleID) else { continue }
            let fullPath = prefsDir + "/\(file)"
            guard resolveAndValidatePath(fullPath, allowedParent: prefsDir) != nil else { continue }
            if !filesToRemove.contains(fullPath) {
                filesToRemove.append(fullPath)
            }
        }
    }

    return filesToRemove
}

private func printUninstallList(_ filesToRemove: [String]) {
    let home = NSHomeDirectory()
    print("Files to remove:")
    var totalSize: Int64 = 0
    for path in filesToRemove {
        let size = fileSize(path)
        totalSize += size
        let sizeStr = formatSize(size)
        let shortPath = path.replacingOccurrences(of: home, with: "~")
        print("  \(sizeStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(shortPath)")
    }
    print("")
    print("Total: \(formatSize(totalSize))")
    print("")
}

private func confirmAndRemove(_ filesToRemove: [String], displayName: String) {
    let fm = FileManager.default

    fputs("Remove all? [y/N] ", stderr)
    guard let answer = readLine(), answer.lowercased() == "y" else {
        print("Cancelled.")
        return
    }

    var failedPaths: [String] = []
    for path in filesToRemove {
        do {
            try fm.removeItem(atPath: path)
        } catch {
            fputs("  Could not remove: \(path) — \(error.localizedDescription)\n", stderr)
            failedPaths.append(path)
        }
    }

    // Separate SIP-protected paths from retryable ones
    let sipDirs = ["/Library/Containers/", "/Library/Group Containers/"]
    let sipPaths = failedPaths.filter { path in sipDirs.contains(where: { path.contains($0) }) }
    let retryPaths = failedPaths.filter { path in !sipDirs.contains(where: { path.contains($0) }) }

    retryWithElevatedPrivileges(retryPaths)

    if !sipPaths.isEmpty {
        let home = NSHomeDirectory()
        fputs("Note: macOS will auto-clean container data after reboot:\n", stderr)
        for path in sipPaths {
            fputs("  \(path.replacingOccurrences(of: home, with: "~"))\n", stderr)
        }
    }

    print("\(displayName) uninstalled.")
}

private func retryWithElevatedPrivileges(_ paths: [String]) {
    guard !paths.isEmpty else { return }

    // Resolve symlinks once and validate — pass resolved paths to eliminate TOCTOU
    let home = NSHomeDirectory()
    let allowedPrefixes = [
        "/Applications/",
        "\(home)/Library/Application Support/",
        "\(home)/Library/Caches/",
        "\(home)/Library/Preferences/",
        "\(home)/Library/Logs/",
        "\(home)/Library/Saved Application State/",
        "\(home)/Library/WebKit/",
        "\(home)/Library/HTTPStorages/",
    ]
    var resolvedPaths: [String] = []
    for path in paths {
        let resolved = (path as NSString).resolvingSymlinksInPath
        guard allowedPrefixes.contains(where: { resolved.hasPrefix($0) }) else {
            fputs("Refusing to elevate removal of unexpected path: \(path)\n", stderr)
            exit(1)
        }
        resolvedPaths.append(resolved)
    }

    fputs("Some files require admin privileges to remove. Requesting access...\n", stderr)

    // Pass resolved paths via argv to avoid both injection and TOCTOU
    let script = """
    on run argv
        repeat with p in argv
            do shell script "/bin/rm -rf " & quoted form of p with administrator privileges
        end repeat
    end run
    """
    let osa = Process()
    osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    osa.arguments = ["-e", script] + resolvedPaths
    do {
        try osa.run()
        osa.waitUntilExit()
    } catch {
        fputs("Failed to request admin privileges: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    if osa.terminationStatus != 0 {
        fputs("Failed to remove some files. Try manually with sudo.\n", stderr)
        exit(1)
    }
}

// MARK: - Helpers

private func resolveAndValidatePath(_ path: String, allowedParent: String) -> String? {
    let resolved = (path as NSString).resolvingSymlinksInPath
    let parentResolved = (allowedParent as NSString).resolvingSymlinksInPath
    guard resolved == parentResolved || resolved.hasPrefix(parentResolved + "/") else { return nil }
    return resolved
}

private func fileSize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var total: Int64 = 0
    var count = 0
    let resolvedBase = (path as NSString).resolvingSymlinksInPath

    if let attrs = try? fm.attributesOfItem(atPath: resolvedBase) {
        if attrs[.type] as? FileAttributeType == .typeDirectory {
            if let enumerator = fm.enumerator(atPath: resolvedBase) {
                while let file = enumerator.nextObject() as? String {
                    count += 1
                    if count > maxFileEnumeration { break }
                    let filePath = resolvedBase + "/\(file)"
                    let resolvedFile = (filePath as NSString).resolvingSymlinksInPath
                    guard resolvedFile.hasPrefix(resolvedBase + "/") else { continue }
                    if let fileAttrs = try? fm.attributesOfItem(atPath: resolvedFile),
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

@discardableResult
private func runProcess(_ path: String, args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fputs("Failed to run \(path): \(error.localizedDescription)\n", stderr)
        return -1
    }
    return process.terminationStatus
}

private func captureProcess(_ path: String, args: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        fputs("Failed to run \(path): \(error.localizedDescription)\n", stderr)
        return nil
    }

    var data = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        data = pipe.fileHandleForReading.readData(ofLength: maxProcessOutput)
        // Drain remaining output to prevent pipe deadlock
        while !pipe.fileHandleForReading.readData(ofLength: 65536).isEmpty {}
        group.leave()
    }
    process.waitUntilExit()
    group.wait()

    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}
