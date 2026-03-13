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
private let configDir = NSHomeDirectory() + "/.config/swiss"
private let twitterConfigFile = NSHomeDirectory() + "/.config/swiss/twitter"

private func readAuthToken() -> String? {
    // 1. Environment variable
    if let token = ProcessInfo.processInfo.environment["TWITTER_AUTH_TOKEN"], !token.isEmpty {
        return token
    }
    // 2. Config file
    if let content = try? String(contentsOfFile: twitterConfigFile, encoding: .utf8) {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("auth_token=") {
                let value = String(trimmed.dropFirst("auth_token=".count)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
    }
    return nil
}

private func saveAuthToken(_ token: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    try? "auth_token=\(token)\n".write(toFile: twitterConfigFile, atomically: true, encoding: .utf8)
}

func runTwitterCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "newsboat", binary: "newsboat")])

    // Handle "auth" subcommand before Docker setup
    if args.first == "auth" {
        handleAuth(args: Array(args.dropFirst()))
        return
    }

    // Ensure Docker + RSSHub are running (skip if custom RSSHUB_URL is set)
    if ProcessInfo.processInfo.environment["RSSHUB_URL"] == nil {
        guard let authToken = readAuthToken() else {
            fputs("Twitter auth token is not configured.\n", stderr)
            fputs("To get your token:\n", stderr)
            fputs("  1. Open x.com in your browser and log in\n", stderr)
            fputs("  2. Open DevTools (F12) -> Application -> Cookies -> x.com\n", stderr)
            fputs("  3. Find the 'auth_token' cookie and copy its value\n", stderr)
            fputs("  4. Run: swiss twitter auth <token>\n", stderr)
            exit(1)
        }
        let docker = ensureDockerReady()
        ensureContainer(
            docker: docker,
            name: rsshubContainerName,
            image: rsshubImage,
            ports: rsshubPort,
            envVars: ["TWITTER_AUTH_TOKEN": authToken]
        )
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
    case "auth":
        handleAuth(args: Array(args.dropFirst()))
    default:
        fputs("Unknown twitter subcommand: \(action)\n", stderr)
        fputs("Usage: swiss twitter [auth|add|remove|list]\n", stderr)
        exit(1)
    }
}

private func handleAuth(args: [String]) {
    guard let token = args.first else {
        if let existing = readAuthToken() {
            let masked = String(existing.prefix(4)) + "..." + String(existing.suffix(4))
            print("Auth token is configured: \(masked)")
        } else {
            print("No auth token configured.")
        }
        print("")
        print("To set your token:")
        print("  1. Open x.com in your browser and log in")
        print("  2. Open DevTools (F12) -> Application -> Cookies -> x.com")
        print("  3. Find the 'auth_token' cookie and copy its value")
        print("  4. Run: swiss twitter auth <token>")
        return
    }
    saveAuthToken(token)
    print("Auth token saved.")
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
