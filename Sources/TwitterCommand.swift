import Foundation

private let urlsFilePath = NSHomeDirectory() + "/.newsboat/urls"
private let rsshubBase: String = {
    if let custom = ProcessInfo.processInfo.environment["RSSHUB_URL"] {
        let base = custom.hasSuffix("/") ? custom : custom + "/"
        return base + "twitter/user/"
    }
    return "http://localhost:1200/twitter/user/"
}()
private let tag = "twitter"
private let rsshubContainerName = "rsshub"
private let rsshubImage = "diygod/rsshub"
private let rsshubPort = "1200:1200"

func runTwitterCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "newsboat", binary: "newsboat")])

    // Ensure Docker + RSSHub are running (skip if custom RSSHUB_URL is set)
    if ProcessInfo.processInfo.environment["RSSHUB_URL"] == nil {
        let docker = ensureDockerReady()
        ensureContainer(docker: docker, name: rsshubContainerName, image: rsshubImage, ports: rsshubPort)
    }

    let dir = NSHomeDirectory() + "/.newsboat"
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir) {
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: urlsFilePath) {
        fm.createFile(atPath: urlsFilePath, contents: nil)
    }

    migrateOldUrls()

    guard let action = args.first else {
        openNewsboat()
        return
    }

    switch action {
    case "add":
        guard args.count >= 2 else {
            fputs("Usage: swiss twitter add <username>\n", stderr)
            exit(1)
        }
        addAccount(args[1])
    case "remove":
        guard args.count >= 2 else {
            fputs("Usage: swiss twitter remove <username>\n", stderr)
            exit(1)
        }
        removeAccount(args[1])
    case "list":
        listAccounts()
    default:
        fputs("Unknown twitter subcommand: \(action)\n", stderr)
        fputs("Usage: swiss twitter [add|remove|list]\n", stderr)
        exit(1)
    }
}

private let legacyRsshubBase = "https://rsshub.app/twitter/user/"

private func readLines() -> [String] {
    guard let content = try? String(contentsOfFile: urlsFilePath, encoding: .utf8) else {
        return []
    }
    return content.components(separatedBy: "\n")
}

private func migrateOldUrls() {
    guard rsshubBase != legacyRsshubBase else { return }
    var lines = readLines()
    var changed = false
    for i in lines.indices {
        if lines[i].hasPrefix(legacyRsshubBase) {
            lines[i] = lines[i].replacingOccurrences(of: legacyRsshubBase, with: rsshubBase)
            changed = true
        }
    }
    if changed {
        writeLines(lines)
        fputs("Migrated feed URLs to local RSSHub instance.\n", stderr)
    }
}

private func isTwitterLine(_ line: String) -> Bool {
    return line.hasPrefix(rsshubBase) || line.hasPrefix(legacyRsshubBase)
}

private func extractUsername(from line: String) -> String {
    return line
        .replacingOccurrences(of: rsshubBase, with: "")
        .replacingOccurrences(of: legacyRsshubBase, with: "")
        .components(separatedBy: " ")
        .first ?? ""
}

private func writeLines(_ lines: [String]) {
    let content = lines.joined(separator: "\n")
    try? content.write(toFile: urlsFilePath, atomically: true, encoding: .utf8)
}

private func feedURL(for username: String) -> String {
    return rsshubBase + username
}

private func addAccount(_ username: String) {
    let username = username.hasPrefix("@") ? String(username.dropFirst()) : username
    let url = feedURL(for: username)
    let lines = readLines()

    if lines.contains(where: { $0.hasPrefix(url) }) {
        print("@\(username) is already added")
        return
    }

    let entry = "\(url) \"~@\(username)\" \(tag)"
    var updated = lines
    if updated.last == "" {
        updated.insert(entry, at: updated.count - 1)
    } else {
        updated.append(entry)
    }
    writeLines(updated)
    print("Added @\(username)")
}

private func removeAccount(_ username: String) {
    let username = username.hasPrefix("@") ? String(username.dropFirst()) : username
    var lines = readLines()
    let before = lines.count

    lines.removeAll { isTwitterLine($0) && extractUsername(from: $0) == username }

    if lines.count == before {
        fputs("@\(username) not found\n", stderr)
        exit(1)
    }

    writeLines(lines)
    print("Removed @\(username)")
}

private func listAccounts() {
    let lines = readLines().filter { $0.contains(" \(tag)") && isTwitterLine($0) }
    if lines.isEmpty {
        print("No twitter accounts. Add one with: swiss twitter add <username>")
        return
    }
    for line in lines {
        print("@\(extractUsername(from: line))")
    }
}

private func openNewsboat() {
    let twitterLines = readLines().filter { isTwitterLine($0) }
    if twitterLines.isEmpty {
        print("No twitter accounts. Add one with: swiss twitter add <username>")
        return
    }

    let tmpDir = NSTemporaryDirectory() + "swiss-twitter"
    let tmpUrls = tmpDir + "/urls"
    let fm = FileManager.default
    try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    try? twitterLines.joined(separator: "\n").write(toFile: tmpUrls, atomically: true, encoding: .utf8)

    let args: [String] = ["newsboat", "-u", tmpUrls, "-r"]
    let argv = args.map { strdup($0) } + [nil]
    execvp("newsboat", argv)

    perror("Failed to exec newsboat")
    exit(1)
}
