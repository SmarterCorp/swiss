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

    case "login":
        cleanLoginItems(force: force, dryRun: dryRun)

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
    print("  login               — remove orphaned background items from uninstalled apps")
    print("  login --dry-run     — show orphaned items without removing")
    print("  login --force       — skip confirmation")
    print("")
    print("Login cleanup parses the BTM database and scans LaunchAgent/Daemon")
    print("directories to find orphaned items, grouped by developer.")
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

// MARK: - Login Items Cleanup

private struct OrphanedItem {
    let label: String
    let developerName: String?
    let itemType: String          // "Launch Agent", "Launch Daemon", "Login Item", "Background Task"
    let location: String          // "user" or "system"
    let plistPath: String?        // nil for BTM-only entries
    let executablePath: String?
    let identifier: String?
}

// MARK: BTM Parser

private struct BTMEntry {
    let name: String
    let developerName: String?
    let type: String              // "legacy agent", "legacy daemon", "login item", "app", "developer"
    let disposition: String
    let identifier: String
    let url: String?
    let executablePath: String?
    let parentIdentifier: String?
    let assocBundleIDs: [String]
    let embeddedItemIDs: [String]
}

private let maxBTMEntries = 10_000

private func parseBTMDump() -> [BTMEntry] {
    guard let output = captureProcess("/usr/bin/sfltool", args: ["dumpbtm"]) else { return [] }
    // Sanity check: verify output looks like BTM dump
    guard output.contains("UUID:") || output.contains("Name:") else { return [] }

    var entries: [BTMEntry] = []
    let lines = output.components(separatedBy: "\n")
    var currentBlock: [String] = []
    var inEntry = false

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: "^#\\d+:", options: .regularExpression) != nil {
            if inEntry && !currentBlock.isEmpty {
                if let entry = parseBTMBlock(currentBlock) {
                    entries.append(entry)
                    if entries.count >= maxBTMEntries { return entries }
                }
            }
            currentBlock = []
            inEntry = true
        } else if inEntry {
            currentBlock.append(line)
        }
    }
    if inEntry && !currentBlock.isEmpty {
        if let entry = parseBTMBlock(currentBlock) {
            entries.append(entry)
        }
    }
    return entries
}

private func parseBTMBlock(_ lines: [String]) -> BTMEntry? {
    let (fields, assocBundleIDs, embeddedItemIDs) = parseBTMFields(lines)
    guard let name = fields["Name"] else { return nil }

    let typeRaw = fields["Type"] ?? ""
    let type = typeRaw.components(separatedBy: " (").first ?? typeRaw

    let dispRaw = fields["Disposition"] ?? ""
    let disposition = dispRaw.components(separatedBy: "] ").first.map { $0 + "]" } ?? dispRaw

    let url = parseBTMURL(fields["URL"])

    return BTMEntry(
        name: name, developerName: fields["Developer Name"],
        type: type, disposition: disposition,
        identifier: fields["Identifier"] ?? name, url: url,
        executablePath: fields["Executable Path"],
        parentIdentifier: fields["Parent Identifier"],
        assocBundleIDs: assocBundleIDs, embeddedItemIDs: embeddedItemIDs
    )
}

private func parseBTMFields(_ lines: [String]) -> ([String: String], [String], [String]) {
    var fields: [String: String] = [:]
    var assocBundleIDs: [String] = []
    var embeddedItemIDs: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let colonRange = trimmed.range(of: ": ") {
            let key = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value != "(null)" { fields[key] = value }
        }
        if trimmed.hasPrefix("Assoc. Bundle IDs:") {
            let content = trimmed.replacingOccurrences(of: "Assoc. Bundle IDs:", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            if !content.isEmpty {
                assocBundleIDs = content.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        if trimmed.range(of: "^#\\d+: ", options: .regularExpression) != nil,
           let range = trimmed.range(of: ": ") {
            embeddedItemIDs.append(String(trimmed[range.upperBound...]))
        }
    }
    return (fields, assocBundleIDs, embeddedItemIDs)
}

private func parseBTMURL(_ raw: String?) -> String? {
    guard let u = raw, u.hasPrefix("file://") else { return raw }
    let decoded = u.replacingOccurrences(of: "file://", with: "")
        .removingPercentEncoding ?? u.replacingOccurrences(of: "file://", with: "")
    return validateBTMPath(decoded)
}

/// Validate a path from BTM dump against allowed directories.
/// Returns resolved path if valid, nil if it could be a traversal or is outside allowed scope.
private func validateBTMPath(_ path: String) -> String? {
    guard !path.isEmpty else { return nil }
    let resolved = (path as NSString).resolvingSymlinksInPath
    let home = NSHomeDirectory()
    let allowedPrefixes = [
        "/Library/LaunchAgents/", "/Library/LaunchDaemons/",
        "\(home)/Library/LaunchAgents/",
        "/Applications/",
    ]
    // Reject relative paths — legitimate BTM entries always use absolute paths
    guard resolved.hasPrefix("/") else { return nil }
    // .app URLs are safe for read-only existence checks — return resolved path
    if resolved.hasSuffix(".app") || resolved.hasSuffix(".app/") {
        return resolved
    }
    // Plist paths must be in known directories
    if allowedPrefixes.contains(where: { resolved.hasPrefix($0) }) {
        return resolved
    }
    return nil
}

// MARK: BTM Orphan Detection

private func scanBTMOrphans(installedApps: [String]) -> [OrphanedItem] {
    let fm = FileManager.default
    let entries = parseBTMDump()
    var orphaned: [OrphanedItem] = []
    // Track all entries by identifier for parent lookups
    var developerEntries: [String: BTMEntry] = [:]
    var allEntriesByID: [String: BTMEntry] = [:]
    var childEntries: [BTMEntry] = []

    for entry in entries {
        if isAppleIdentifier(entry.identifier) { continue }
        allEntriesByID[entry.identifier] = entry
        if entry.type == "developer" {
            developerEntries[entry.identifier] = entry
        } else {
            childEntries.append(entry)
        }
    }

    // Deduplicate child entries by identifier (BTM has duplicates across UID sections)
    var seenIdentifiers = Set<String>()

    for entry in childEntries {
        if isAppleIdentifier(entry.identifier) { continue }
        // Skip "quicklook" and "spotlight" types — these are harmless embedded plugins
        if entry.type == "quicklook" || entry.type == "spotlight" { continue }
        guard seenIdentifiers.insert(entry.identifier).inserted else { continue }

        if !btmEntryHasInstalledApp(entry, fm: fm, installedApps: installedApps,
                                     allEntries: allEntriesByID) {
            let devName = resolveDeveloperName(entry, developerEntries: developerEntries)
            let itemType = btmTypeToDisplay(entry.type)
            let location = btmLocationFromEntry(entry)
            orphaned.append(OrphanedItem(
                label: cleanIdentifier(entry.identifier),
                developerName: devName,
                itemType: itemType,
                location: location,
                plistPath: entry.url,
                executablePath: entry.executablePath,
                identifier: entry.identifier
            ))
        }
    }

    return orphaned
}

/// Derive developer/vendor name from plist filename
/// e.g. "com.piriform.ccleaner.plist" → "Piriform", "at.obdev.littlesnitch.agent.plist" → "Obdev"
private func developerNameFromPlistFilename(_ filename: String) -> String? {
    let name = filename.replacingOccurrences(of: ".plist", with: "")
    let parts = name.components(separatedBy: ".")
    guard parts.count >= 2 else { return nil }
    // Use second component as vendor (com.vendor.product or at.vendor.product)
    let vendor = parts[1]
    guard !vendor.isEmpty else { return nil }
    return vendor.prefix(1).uppercased() + vendor.dropFirst()
}

private func resolveDeveloperName(_ entry: BTMEntry, developerEntries: [String: BTMEntry]) -> String? {
    // Try parent identifier first
    if let pid = entry.parentIdentifier, pid != "Unknown Developer" {
        if let dev = developerEntries[pid] { return dev.name }
        return pid
    }
    // Try developer name from entry itself
    if let devName = entry.developerName { return devName }
    // Derive from identifier: com.box.desktop.launch → "Box" (capitalize vendor)
    let cleaned = cleanIdentifier(entry.identifier)
    let parts = cleaned.components(separatedBy: ".")
    if parts.count >= 2 {
        let vendor = parts[1]
        return vendor.prefix(1).uppercased() + vendor.dropFirst()
    }
    // Derive from plist URL filename: com.webroot.security.mac.plist → "Webroot"
    if let url = entry.url {
        let filename = (url as NSString).lastPathComponent
        if let name = developerNameFromPlistFilename(filename) {
            return name
        }
    }
    // Last resort: use entry name
    return entry.name
}

private func isAppleIdentifier(_ identifier: String) -> Bool {
    let cleaned = cleanIdentifier(identifier)
    return cleaned.hasPrefix("com.apple.")
}

/// Strip BTM type prefix (e.g. "16.com.foo" → "com.foo", "8.com.bar" → "com.bar")
private func cleanIdentifier(_ identifier: String) -> String {
    let parts = identifier.components(separatedBy: ".")
    guard parts.count >= 2, let first = parts.first, Int(first) != nil else { return identifier }
    return parts.dropFirst().joined(separator: ".")
}

/// Determine location from plist path (more reliable than BTM type)
private func btmLocationFromEntry(_ entry: BTMEntry) -> String {
    if let url = entry.url {
        if url.hasPrefix("/Library/LaunchDaemons/") || url.hasPrefix("/Library/LaunchAgents/") {
            return "system"
        }
    }
    if entry.type.contains("daemon") { return "system" }
    return "user"
}

private func btmTypeToDisplay(_ type: String) -> String {
    switch type {
    case "legacy agent":  return "Launch Agent"
    case "legacy daemon": return "Launch Daemon"
    case "login item":    return "Login Item"
    case "app":           return "App"
    default:              return "Background Task"
    }
}

private func btmEntryHasInstalledApp(_ entry: BTMEntry, fm: FileManager, installedApps: [String],
                                     allEntries: [String: BTMEntry]) -> Bool {
    // Check parent app existence (login items belong to a parent app)
    if btmParentAppExists(entry, fm: fm, installedApps: installedApps, allEntries: allEntries) {
        return true
    }
    // Check URL — app-type entries have URL pointing to .app bundle
    if let url = entry.url,
       (url.hasSuffix(".app/") || url.hasSuffix(".app")),
       fm.fileExists(atPath: url) {
        return true
    }
    // Check executable path (skip helpers that persist after uninstall)
    if btmExecutableExists(entry, fm: fm, installedApps: installedApps) { return true }
    // Check associated bundle IDs — exact match only (not vendor prefix)
    if btmAssocBundleIDsMatch(entry, installedApps: installedApps) { return true }
    return false
}

private func btmParentAppExists(_ entry: BTMEntry, fm: FileManager, installedApps: [String],
                                 allEntries: [String: BTMEntry]) -> Bool {
    guard let parentID = entry.parentIdentifier, parentID != "Unknown Developer",
          let parent = allEntries[parentID] else { return false }
    if let parentURL = parent.url,
       (parentURL.hasSuffix(".app/") || parentURL.hasSuffix(".app")),
       fm.fileExists(atPath: parentURL) {
        return true
    }
    return matchesInstalledApp(cleanIdentifier(parentID), installedApps: installedApps)
}

private func btmExecutableExists(_ entry: BTMEntry, fm: FileManager, installedApps: [String]) -> Bool {
    let systemBinaries = ["/usr/bin/open", "/usr/bin/osascript", "/usr/bin/env", "/bin/sh", "/bin/bash"]
    guard let exePath = entry.executablePath, !systemBinaries.contains(exePath) else {
        // For /usr/bin/open -b style: check ProgramArguments for bundle ID
        return btmOpenBundleIDExists(entry, installedApps: installedApps)
    }
    // Helper tools in certain directories persist after the main app is uninstalled
    let home = NSHomeDirectory()
    let helperPrefixes = [
        "/Library/PrivilegedHelperTools/", "/usr/local/libexec/",
        "\(home)/Library/Application Support/", "/Library/Application Support/",
    ]
    if helperPrefixes.contains(where: { exePath.hasPrefix($0) }) { return false }
    if let appPath = extractAppPath(from: exePath), fm.fileExists(atPath: appPath) { return true }
    return fm.fileExists(atPath: exePath)
}

private func btmOpenBundleIDExists(_ entry: BTMEntry, installedApps: [String]) -> Bool {
    guard entry.executablePath == "/usr/bin/open", let plistPath = entry.url else { return false }
    // Only read plists from known safe directories
    let home = NSHomeDirectory()
    let safeDirs = ["/Library/LaunchAgents/", "/Library/LaunchDaemons/", "\(home)/Library/LaunchAgents/"]
    let resolved = (plistPath as NSString).resolvingSymlinksInPath
    guard safeDirs.contains(where: { resolved.hasPrefix($0) }) else { return false }
    guard let plist = NSDictionary(contentsOfFile: resolved),
          let args = plist["ProgramArguments"] as? [String] else { return false }
    for (i, arg) in args.enumerated() where arg == "-b" && i + 1 < args.count {
        if matchesInstalledApp(args[i + 1], installedApps: installedApps) { return true }
    }
    return false
}

private func btmAssocBundleIDsMatch(_ entry: BTMEntry, installedApps: [String]) -> Bool {
    // Exact match only — com.macpaw.CleanMyMac4 should not match ClearVPN (com.macpaw.clearvpn)
    for bundleID in entry.assocBundleIDs {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil { return true }
        if installedApps.contains(bundleID) { return true }
    }
    // Vendor prefix match only without explicit associated bundle IDs
    if entry.assocBundleIDs.isEmpty {
        let cleaned = cleanIdentifier(entry.identifier)
        if let prefix = vendorPrefixFromFilename(cleaned + ".plist") {
            if installedApps.contains(where: { $0.hasPrefix(prefix) }) { return true }
        }
    }
    return false
}

// MARK: Combined Scan & Display

private func cleanLoginItems(force: Bool, dryRun: Bool) {
    fputs("Scanning background items...\n", stderr)
    let allOrphaned = scanAllOrphanedItems()

    if allOrphaned.isEmpty {
        if jsonMode {
            printJSON(["orphaned": [] as [Any], "count": 0])
        } else {
            print("No orphaned background items found.")
        }
        return
    }

    if jsonMode {
        printOrphanedJSON(allOrphaned, dryRun: dryRun)
        return
    }

    printOrphanedItems(allOrphaned)
    if dryRun {
        print("(dry run — nothing removed)")
        return
    }

    if !force && !confirmOrphanRemoval(allOrphaned) { return }

    let removable = allOrphaned.filter { $0.plistPath != nil }
    let removed = removeOrphanedItems(removable)
    resetLoginDatabase()
    print("\nRemoved \(removed) orphaned items.")
    print("Reboot your Mac for changes to take effect.")
}

private func scanAllOrphanedItems() -> [OrphanedItem] {
    let installedApps = loadInstalledAppBundleIDs()
    let btmOrphans = scanBTMOrphans(installedApps: installedApps)
    let plistOrphans = scanOrphanedAgents(installedApps: installedApps)
    // Merge: BTM items take priority, add plist-only items
    let btmPlistPaths = Set(btmOrphans.compactMap { $0.plistPath })
    let plistOnly = plistOrphans.filter { item in
        guard let path = item.plistPath else { return true }
        return !btmPlistPaths.contains(path)
    }
    return btmOrphans + plistOnly
}

private func printOrphanedJSON(_ orphaned: [OrphanedItem], dryRun: Bool) {
    let items = orphaned.map { item -> [String: Any] in
        var dict: [String: Any] = [
            "label": item.label, "type": item.itemType, "location": item.location,
        ]
        if let dev = item.developerName { dict["developer_name"] = dev }
        if let path = item.plistPath { dict["plist_path"] = path }
        if let exe = item.executablePath { dict["executable_path"] = exe }
        if let id = item.identifier { dict["identifier"] = id }
        return dict
    }
    printJSON(["orphaned": items, "count": orphaned.count, "dry_run": dryRun])
}

private func confirmOrphanRemoval(_ orphaned: [OrphanedItem]) -> Bool {
    let plistCount = orphaned.filter { $0.plistPath != nil }.count
    let btmOnlyCount = orphaned.filter { $0.plistPath == nil }.count
    var prompt = "Remove \(plistCount) orphaned plist files"
    if btmOnlyCount > 0 {
        prompt += " and reset login database (\(btmOnlyCount) BTM-only entries)"
    }
    prompt += "? [y/N] "
    fputs(prompt, stderr)
    guard let answer = readLine(), answer.lowercased() == "y" else {
        print("Cancelled.")
        return false
    }
    return true
}

private func scanOrphanedAgents(installedApps: [String]) -> [OrphanedItem] {
    let fm = FileManager.default
    let home = NSHomeDirectory()
    let scanDirs: [(path: String, location: String)] = [
        ("\(home)/Library/LaunchAgents", "user"),
        ("/Library/LaunchAgents", "system"),
        ("/Library/LaunchDaemons", "system"),
    ]
    var orphaned: [OrphanedItem] = []

    for dir in scanDirs {
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
        var count = 0
        for file in files where file.hasSuffix(".plist") {
            count += 1
            if count > maxFileEnumeration { break }
            let fullPath = dir.path + "/\(file)"
            if !agentHasInstalledApp(plistPath: fullPath, fm: fm, installedApps: installedApps) {
                let label = extractAgentLabel(plistPath: fullPath) ?? file
                let itemType = dir.path.contains("LaunchDaemons") ? "Launch Daemon" : "Launch Agent"
                let devName = developerNameFromPlistFilename(file)
                orphaned.append(OrphanedItem(
                    label: label,
                    developerName: devName,
                    itemType: itemType,
                    location: dir.location,
                    plistPath: fullPath,
                    executablePath: nil,
                    identifier: nil
                ))
            }
        }
    }
    return orphaned
}

private func printOrphanedItems(_ orphaned: [OrphanedItem]) {
    // Group by developer name
    var grouped: [(developer: String, items: [OrphanedItem])] = []
    var byDev: [String: [OrphanedItem]] = [:]
    var devOrder: [String] = []

    for item in orphaned {
        let key = item.developerName ?? "Unknown Developer"
        if byDev[key] == nil { devOrder.append(key) }
        byDev[key, default: []].append(item)
    }
    for key in devOrder {
        if let items = byDev[key] {
            grouped.append((developer: key, items: items))
        }
    }

    let totalItems = orphaned.count
    let removable = orphaned.filter { $0.plistPath != nil }.count
    let btmOnly = totalItems - removable

    print("Orphaned background items (\(totalItems)):\n")

    for group in grouped {
        let countSuffix = group.items.count > 1 ? " (\(group.items.count) items)" : ""
        print("  \(group.developer)\(countSuffix)")
        for item in group.items {
            let typeTag = item.itemType
            let locTag = item.location == "system" ? ", system" : ""
            let label = item.label
            print("    \(label)  (\(typeTag)\(locTag))")
        }
        print("")
    }

    if btmOnly > 0 {
        print("  Note: \(btmOnly) items exist only in the BTM database (no plist file).")
        print("  These will be cleared by resetting the login items database.\n")
    }
}

private func removeOrphanedItems(_ items: [OrphanedItem]) -> Int {
    let fm = FileManager.default
    let home = NSHomeDirectory()
    let userItems = items.filter { $0.location == "user" }
    let systemItems = items.filter { $0.location == "system" }
    var removed = 0

    // Remove user-level agents with symlink validation
    let userAgentsDir = "\(home)/Library/LaunchAgents"
    for item in userItems {
        guard let plistPath = item.plistPath else { continue }
        let resolved = (plistPath as NSString).resolvingSymlinksInPath
        guard resolved.hasPrefix(userAgentsDir + "/") else {
            fputs("  Skipping (resolved outside LaunchAgents): \(plistPath)\n", stderr)
            continue
        }
        unloadAgent(path: resolved, system: false)
        do {
            try fm.removeItem(atPath: resolved)
            removed += 1
        } catch {
            fputs("  Failed to remove: \(plistPath) — \(error.localizedDescription)\n", stderr)
        }
    }

    // Remove system-level agents/daemons via elevated privileges
    let systemPaths = systemItems.compactMap { $0.plistPath }
    if !systemPaths.isEmpty {
        for path in systemPaths {
            unloadAgent(path: path, system: true)
        }
        let systemRemoved = removeSystemPlists(systemPaths)
        removed += systemRemoved
    }

    return removed
}

private func resetLoginDatabase() {
    fputs("Resetting login items database...\n", stderr)

    if geteuid() == 0 {
        // Already root — run directly
        let status = runProcess("/usr/bin/sfltool", args: ["resetbtm"])
        if status != 0 {
            fputs("Failed to reset login items database (exit \(status)).\n", stderr)
        }
    } else {
        let script = "do shell script \"/usr/bin/sfltool resetbtm\" with administrator privileges"
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        do {
            try osa.run()
            osa.waitUntilExit()
        } catch {
            fputs("Failed to reset login items database: \(error.localizedDescription)\n", stderr)
            return
        }
        if osa.terminationStatus != 0 {
            fputs("Failed to reset login items database. Try: sudo sfltool resetbtm\n", stderr)
        }
    }
}

private func extractAgentLabel(plistPath: String) -> String? {
    guard let plist = NSDictionary(contentsOfFile: plistPath) else { return nil }
    return plist["Label"] as? String
}

private func loadInstalledAppBundleIDs() -> [String] {
    let fm = FileManager.default
    guard let apps = try? fm.contentsOfDirectory(atPath: "/Applications") else { return [] }
    var bundleIDs: [String] = []
    for app in apps where app.hasSuffix(".app") {
        let plistPath = "/Applications/\(app)/Contents/Info.plist"
        if let plist = NSDictionary(contentsOfFile: plistPath),
           let bundleID = plist["CFBundleIdentifier"] as? String {
            bundleIDs.append(bundleID)
        }
    }
    return bundleIDs
}

private func agentHasInstalledApp(plistPath: String, fm: FileManager, installedApps: [String]) -> Bool {
    let plist = NSDictionary(contentsOfFile: plistPath)

    // Check ProgramArguments for executable path
    if let programArgs = plist?["ProgramArguments"] as? [String],
       let executable = programArgs.first {
        if fm.fileExists(atPath: executable) { return true }
        if let appPath = extractAppPath(from: executable), fm.fileExists(atPath: appPath) {
            return true
        }
    }

    // Check Program key
    if let program = plist?["Program"] as? String {
        if fm.fileExists(atPath: program) { return true }
        if let appPath = extractAppPath(from: program), fm.fileExists(atPath: appPath) {
            return true
        }
    }

    // Check AssociatedBundleIdentifiers — some daemons belong to apps
    // installed under a different bundle ID (e.g. SoundSource uses com.rogueamoeba.ace daemons)
    if let associated = plist?["AssociatedBundleIdentifiers"] as? String {
        if matchesInstalledApp(associated, installedApps: installedApps) { return true }
    } else if let associated = plist?["AssociatedBundleIdentifiers"] as? [String] {
        for bundleID in associated {
            if matchesInstalledApp(bundleID, installedApps: installedApps) { return true }
        }
    }

    // Fallback: if plist is empty or has no executable, derive vendor prefix from filename
    // e.g. com.google.keystone.agent.plist → com.google → matches Google Chrome
    let filename = (plistPath as NSString).lastPathComponent
    if let vendorPrefix = vendorPrefixFromFilename(filename) {
        if installedApps.contains(where: { $0.hasPrefix(vendorPrefix) }) { return true }
    }

    return false
}

private func matchesInstalledApp(_ bundleID: String, installedApps: [String]) -> Bool {
    // Exact match
    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
        return true
    }
    // Vendor prefix match: com.rogueamoeba.ace → com.rogueamoeba
    let components = bundleID.components(separatedBy: ".")
    guard components.count >= 2 else { return false }
    let vendorPrefix = components[0...1].joined(separator: ".")
    return installedApps.contains(where: { $0.hasPrefix(vendorPrefix) })
}

private func vendorPrefixFromFilename(_ filename: String) -> String? {
    let name = filename.replacingOccurrences(of: ".plist", with: "")
    let parts = name.components(separatedBy: ".")
    guard parts.count >= 2 else { return nil }
    return parts[0...1].joined(separator: ".")
}

private func extractAppPath(from executablePath: String) -> String? {
    // Extract /Applications/Foo.app from paths like /Applications/Foo.app/Contents/MacOS/foo
    let components = executablePath.components(separatedBy: "/")
    for (i, component) in components.enumerated() where component.hasSuffix(".app") {
        return components[0...i].joined(separator: "/")
    }
    return nil
}

private func unloadAgent(path: String, system: Bool) {
    // Validate path before passing to launchctl
    let resolved = (path as NSString).resolvingSymlinksInPath
    let allowedPrefixes = ["/Library/LaunchAgents/", "/Library/LaunchDaemons/",
                           NSHomeDirectory() + "/Library/LaunchAgents/"]
    guard allowedPrefixes.contains(where: { resolved.hasPrefix($0) }) else {
        fputs("  Skipping unload (path outside allowed scope): \(path)\n", stderr)
        return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    if system {
        process.arguments = ["bootout", "system", resolved]
    } else {
        let uid = getuid()
        process.arguments = ["bootout", "gui/\(uid)", resolved]
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fputs("  Failed to unload agent: \(error.localizedDescription)\n", stderr)
    }
}

@discardableResult
private func removeSystemPlists(_ paths: [String]) -> Int {
    let allowedPrefixes = ["/Library/LaunchAgents/", "/Library/LaunchDaemons/"]
    var resolvedPaths: [String] = []
    for path in paths {
        let resolved = (path as NSString).resolvingSymlinksInPath
        guard allowedPrefixes.contains(where: { resolved.hasPrefix($0) }) else {
            fputs("  Skipping (resolved outside allowed scope): \(path)\n", stderr)
            continue
        }
        resolvedPaths.append(resolved)
    }
    guard !resolvedPaths.isEmpty else { return 0 }

    if geteuid() == 0 {
        return removeSystemPlistsAsRoot(resolvedPaths)
    } else {
        return removeSystemPlistsViaOsascript(resolvedPaths)
    }
}

private func removeSystemPlistsAsRoot(_ paths: [String]) -> Int {
    let fm = FileManager.default
    var removed = 0
    for path in paths {
        do {
            try fm.removeItem(atPath: path)
            removed += 1
        } catch {
            fputs("  Failed to remove: \(path) — \(error.localizedDescription)\n", stderr)
        }
    }
    return removed
}

private func removeSystemPlistsViaOsascript(_ resolvedPaths: [String]) -> Int {
    let script = """
    on run argv
        repeat with p in argv
            do shell script "/bin/rm -f " & quoted form of p with administrator privileges
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
        return 0
    }
    return osa.terminationStatus == 0 ? resolvedPaths.count : 0
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
