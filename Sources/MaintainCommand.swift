import Foundation

private let brewPackages = ["newsboat", "ollama", "dua-cli", "bottom"]
private let brewCasks = ["docker", "espanso", "1password-cli"]
private let ollamaModel = "gemma3"
private let rsshubImage = "diygod/rsshub"
private let rsshubContainer = "rsshub"

func runMaintainCommand() {
    var step = 1
    let total = 5

    // 1. Brew packages
    printStep(step, total, "Updating Homebrew packages...")
    step += 1
    if let brew = findBrew() {
        runVisible(brew, args: ["upgrade"] + brewPackages)
    } else {
        fputs("  Homebrew not found, skipping.\n", stderr)
    }

    // 2. Brew casks (Docker, Espanso)
    printStep(step, total, "Updating desktop apps (Docker, Espanso)...")
    step += 1
    if let brew = findBrew() {
        runVisible(brew, args: ["upgrade", "--cask"] + brewCasks)
    }

    // 3. RSSHub container
    printStep(step, total, "Pulling latest RSSHub image...")
    step += 1
    if runSilent("/usr/bin/env", args: ["docker", "info"]) {
        runVisible("/usr/bin/env", args: ["docker", "pull", rsshubImage])
        // Remove old container so it gets recreated with fresh image
        if runSilent("/usr/bin/env", args: ["docker", "inspect", rsshubContainer]) {
            fputs("  Removing old container (will recreate on next use)...\n", stderr)
            _ = runSilent("/usr/bin/env", args: ["docker", "rm", "-f", rsshubContainer])
        }
    } else {
        fputs("  Docker not running, skipping.\n", stderr)
    }

    // 4. Ollama model
    printStep(step, total, "Updating Ollama model (\(ollamaModel))...")
    step += 1
    if runSilent("/usr/bin/env", args: ["ollama", "list"]) {
        runVisible("/usr/bin/env", args: ["ollama", "pull", ollamaModel])
    } else {
        fputs("  Ollama not running, skipping.\n", stderr)
    }

    // 5. Pipit
    printStep(step, total, "Checking Pipit updates...")
    updatePipit()

    print("")
    print("Done.")
}

// MARK: - Helpers

private func printStep(_ step: Int, _ total: Int, _ message: String) {
    print("")
    print("[\(step)/\(total)] \(message)")
}

private func findBrew() -> String? {
    findBrewPath()
}

private func runVisible(_ path: String, args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    try? process.run()
    process.waitUntilExit()
}

@discardableResult
private func runSilent(_ path: String, args: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func runCapture(_ path: String, args: [String]) -> String? {
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

// MARK: - Pipit update

private func updatePipit() {
    let appPath = "/Applications/Pipit.app"
    guard FileManager.default.fileExists(atPath: appPath) else {
        fputs("  Pipit not installed, skipping.\n", stderr)
        return
    }

    // Get installed version from Info.plist
    let plistPath = appPath + "/Contents/Info.plist"
    let installedVersion: String
    if let plist = NSDictionary(contentsOfFile: plistPath),
       let version = plist["CFBundleShortVersionString"] as? String {
        installedVersion = version
    } else {
        installedVersion = "unknown"
    }

    // Check latest GitHub release
    guard let latestJSON = runCapture("/usr/bin/curl", args: [
        "-s", "--max-time", "10",
        "-H", "Accept: application/vnd.github+json",
        "https://api.github.com/repos/pxkan/Pipit-Releases/releases/latest",
    ]) else {
        fputs("  Could not check for updates.\n", stderr)
        return
    }

    guard let jsonData = latestJSON.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let tagName = json["tag_name"] as? String else {
        fputs("  Could not parse release info.\n", stderr)
        return
    }

    let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

    if installedVersion == latestVersion {
        print("  Pipit \(installedVersion) (up to date)")
    } else {
        print("  Pipit \(installedVersion) -> \(latestVersion), updating...")
        // Find DMG download URL
        if let assets = json["assets"] as? [[String: Any]],
           let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
           let downloadURL = dmgAsset["browser_download_url"] as? String {
            installPipitUpdate(from: downloadURL)
        } else {
            fputs("  Could not find DMG in release assets.\n", stderr)
        }
    }
}

private func installPipitUpdate(from url: String) {
    let tmpDmg = NSTemporaryDirectory() + "Pipit-update.dmg"
    let fm = FileManager.default

    // Download
    runVisible("/usr/bin/curl", args: ["-L", "-o", tmpDmg, "--progress-bar", url])

    // Mount
    guard let mountOutput = runCapture("/usr/bin/hdiutil", args: ["attach", tmpDmg, "-nobrowse", "-quiet"]) else {
        fputs("  Failed to mount DMG.\n", stderr)
        try? fm.removeItem(atPath: tmpDmg)
        return
    }

    let volumePath = mountOutput.components(separatedBy: "\t").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/Volumes/Pipit"
    let sourceApp = volumePath + "/Pipit.app"
    let destApp = "/Applications/Pipit.app"

    // Kill Pipit if running
    _ = runSilent("/usr/bin/pkill", args: ["-x", "Pipit"])
    Thread.sleep(forTimeInterval: 1)

    // Replace
    try? fm.removeItem(atPath: destApp)
    let copy = Process()
    copy.executableURL = URL(fileURLWithPath: "/bin/cp")
    copy.arguments = ["-R", sourceApp, destApp]
    try? copy.run()
    copy.waitUntilExit()

    // Cleanup
    _ = runSilent("/usr/bin/hdiutil", args: ["detach", volumePath, "-quiet"])
    try? fm.removeItem(atPath: tmpDmg)

    print("  Pipit updated.")
}
