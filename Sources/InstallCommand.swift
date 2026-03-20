import Foundation

// MARK: - App catalog

private enum InstallMethod {
    case formula(package: String, binary: String)
    case cask(package: String, appName: String?)
    case dmg(url: String, appName: String)
}

private struct AppEntry {
    let name: String
    let description: String
    let method: InstallMethod

    var isInstalled: Bool {
        switch method {
        case .formula(_, let binary):
            return commandExists(binary)
        case .cask(_, let appName):
            if let app = appName {
                return FileManager.default.fileExists(atPath: "/Applications/\(app).app")
            }
            // CLI-only casks: check via brew list
            return false
        case .dmg(_, let appName):
            return FileManager.default.fileExists(atPath: "/Applications/\(appName).app")
        }
    }
}

private let catalog: [AppEntry] = [
    // CLI tools
    AppEntry(name: "newsboat", description: "RSS reader", method: .formula(package: "newsboat", binary: "newsboat")),
    AppEntry(name: "ollama", description: "Local LLM runtime", method: .formula(package: "ollama", binary: "ollama")),
    AppEntry(name: "dua", description: "Disk usage analyzer", method: .formula(package: "dua-cli", binary: "dua")),
    AppEntry(name: "btm", description: "System monitor", method: .formula(package: "bottom", binary: "btm")),
    AppEntry(name: "op", description: "1Password CLI", method: .formula(package: "1password-cli", binary: "op")),

    // Desktop apps
    AppEntry(name: "docker", description: "Container runtime", method: .cask(package: "docker", appName: "Docker")),
    AppEntry(name: "espanso", description: "Text expander", method: .cask(package: "espanso", appName: "Espanso")),
    AppEntry(name: "thock", description: "Mechanical keyboard sounds", method: .cask(package: "thock", appName: "Thock")),
    AppEntry(name: "ghostty", description: "GPU-accelerated terminal", method: .cask(package: "ghostty", appName: "Ghostty")),
]

// MARK: - Entry point

func runInstallCommand(args: [String]) {
    if args.first == "--list" || args.first == "list" {
        printCatalog()
        return
    }

    guard let brew = findBrewPath() else {
        fputs("Error: Homebrew is not installed.\n", stderr)
        fputs("Install: https://brew.sh\n", stderr)
        exit(1)
    }

    let appsToInstall: [AppEntry]
    if let name = args.first {
        guard let entry = catalog.first(where: { $0.name == name }) else {
            fputs("Unknown app: \(name)\n", stderr)
            fputs("Run 'swiss install list' to see available apps.\n", stderr)
            exit(1)
        }
        appsToInstall = [entry]
    } else {
        appsToInstall = catalog
    }

    let pending = appsToInstall.filter { !$0.isInstalled }

    if pending.isEmpty {
        print("All apps already installed.")
        return
    }

    print("Installing \(pending.count) app\(pending.count == 1 ? "" : "s")...\n")

    // Group by method for batch installs
    let formulas = pending.compactMap { entry -> String? in
        if case .formula(let pkg, _) = entry.method { return pkg }
        return nil
    }
    let casks = pending.compactMap { entry -> String? in
        if case .cask(let pkg, _) = entry.method { return pkg }
        return nil
    }
    let dmgs = pending.filter {
        if case .dmg = $0.method { return true }
        return false
    }

    var step = 0
    let total = (formulas.isEmpty ? 0 : 1) + (casks.isEmpty ? 0 : 1) + dmgs.count

    if !formulas.isEmpty {
        step += 1
        printStep(step, total, "Installing CLI tools: \(formulas.joined(separator: ", "))")
        runProcess(brew, args: ["install"] + formulas)
    }

    if !casks.isEmpty {
        step += 1
        printStep(step, total, "Installing desktop apps: \(casks.joined(separator: ", "))")
        runProcess(brew, args: ["install", "--cask"] + casks)
    }

    for entry in dmgs {
        step += 1
        if case .dmg(let url, let appName) = entry.method {
            printStep(step, total, "Installing \(appName)")
            installDMGApp(url: url, appName: appName)
        }
    }

    print("\nDone.")
}

// MARK: - List

private func printCatalog() {
    let maxName = catalog.map(\.name.count).max() ?? 0
    let maxDesc = catalog.map(\.description.count).max() ?? 0

    print("Available apps:\n")
    for entry in catalog {
        let status = entry.isInstalled ? "installed" : "missing"
        let marker = entry.isInstalled ? "+" : "-"
        let name = entry.name.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
        let desc = entry.description.padding(toLength: maxDesc + 2, withPad: " ", startingAt: 0)
        print("  [\(marker)] \(name)\(desc)\(status)")
    }

    let installed = catalog.filter(\.isInstalled).count
    print("\n\(installed)/\(catalog.count) installed")
}

// MARK: - DMG installer

private func installDMGApp(url: String, appName: String) {
    let fm = FileManager.default
    let tmpDmg = NSTemporaryDirectory() + "\(appName).dmg"
    let destApp = "/Applications/\(appName).app"

    // Download
    fputs("  Downloading...\n", stderr)
    runProcess("/usr/bin/curl", args: ["-L", "-o", tmpDmg, "--progress-bar", url])

    // Mount
    fputs("  Mounting...\n", stderr)
    guard let mountOutput = captureProcess("/usr/bin/hdiutil", args: ["attach", tmpDmg, "-nobrowse", "-quiet"]) else {
        fputs("  Error: Failed to mount DMG.\n", stderr)
        try? fm.removeItem(atPath: tmpDmg)
        return
    }

    let volumePath = mountOutput.components(separatedBy: "\t").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/Volumes/\(appName)"
    let sourceApp = volumePath + "/\(appName).app"

    guard fm.fileExists(atPath: sourceApp) else {
        fputs("  Error: \(appName).app not found in DMG.\n", stderr)
        detachDMG(volumePath)
        try? fm.removeItem(atPath: tmpDmg)
        return
    }

    // Copy to /Applications
    fputs("  Installing to /Applications...\n", stderr)
    let copy = Process()
    copy.executableURL = URL(fileURLWithPath: "/bin/cp")
    copy.arguments = ["-R", sourceApp, destApp]
    try? copy.run()
    copy.waitUntilExit()

    detachDMG(volumePath)
    try? fm.removeItem(atPath: tmpDmg)

    if copy.terminationStatus != 0 {
        fputs("  Error: Failed to copy \(appName).app.\n", stderr)
        return
    }

    // Verify code signature
    let verify = Process()
    verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    verify.arguments = ["--verify", "--deep", "--strict", destApp]
    verify.standardOutput = FileHandle.nullDevice
    verify.standardError = FileHandle.nullDevice
    try? verify.run()
    verify.waitUntilExit()

    if verify.terminationStatus != 0 {
        fputs("  Warning: \(appName).app failed code signature verification.\n", stderr)
        try? fm.removeItem(atPath: destApp)
        fputs("  Removed unsigned app for safety.\n", stderr)
        return
    }

    fputs("  \(appName) installed (signature verified).\n", stderr)
}

// MARK: - Helpers

private func printStep(_ step: Int, _ total: Int, _ message: String) {
    print("[\(step)/\(total)] \(message)")
}

private func commandExists(_ name: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func runProcess(_ path: String, args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    try? process.run()
    process.waitUntilExit()
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
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func detachDMG(_ volumePath: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = ["detach", volumePath, "-quiet"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}
