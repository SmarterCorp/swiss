import Foundation

private let appName = "Pipit"
private let appPath = "/Applications/\(appName).app"
private let dmgURL = "https://github.com/pxkan/Pipit-Releases/releases/download/v1.2.5/Pipit-1.2.5.dmg"
private let pipitDomain = "com.pxkan.pipit2"

func runVoiceCommand() {
    let freshInstall = !FileManager.default.fileExists(atPath: appPath)
    if freshInstall {
        installPipit()
        configurePipit()
    }

    fputs("Launching \(appName)...\n", stderr)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", appName]
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fputs("Error: Failed to launch \(appName).\n", stderr)
        exit(1)
    }
}

private func installPipit() {
    let tmpDmg = NSTemporaryDirectory() + "Pipit.dmg"

    fputs("Downloading \(appName)...\n", stderr)
    let download = Process()
    download.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    download.arguments = ["-L", "-o", tmpDmg, "--progress-bar", dmgURL]
    download.standardError = FileHandle.standardError
    try? download.run()
    download.waitUntilExit()

    guard download.terminationStatus == 0 else {
        fputs("Error: Failed to download \(appName).\n", stderr)
        exit(1)
    }

    fputs("Mounting DMG...\n", stderr)
    let mount = Process()
    let mountPipe = Pipe()
    mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    mount.arguments = ["attach", tmpDmg, "-nobrowse", "-quiet"]
    mount.standardOutput = mountPipe
    mount.standardError = FileHandle.nullDevice
    try? mount.run()

    var mountData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        mountData = mountPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    mount.waitUntilExit()
    group.wait()

    guard mount.terminationStatus == 0 else {
        fputs("Error: Failed to mount DMG.\n", stderr)
        try? FileManager.default.removeItem(atPath: tmpDmg)
        exit(1)
    }

    // Find the mounted volume
    let mountOutput = String(data: mountData, encoding: .utf8) ?? ""
    let volumePath = mountOutput.components(separatedBy: "\t").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/Volumes/Pipit"

    let sourceApp = volumePath + "/\(appName).app"
    guard FileManager.default.fileExists(atPath: sourceApp) else {
        fputs("Error: \(appName).app not found in DMG at \(sourceApp).\n", stderr)
        detach(volumePath)
        try? FileManager.default.removeItem(atPath: tmpDmg)
        exit(1)
    }

    fputs("Installing to /Applications...\n", stderr)
    let copy = Process()
    copy.executableURL = URL(fileURLWithPath: "/bin/cp")
    copy.arguments = ["-R", sourceApp, appPath]
    try? copy.run()
    copy.waitUntilExit()

    if copy.terminationStatus != 0 {
        fputs("Error: Failed to copy \(appName).app to /Applications.\n", stderr)
        detach(volumePath)
        try? FileManager.default.removeItem(atPath: tmpDmg)
        exit(1)
    }

    detach(volumePath)
    try? FileManager.default.removeItem(atPath: tmpDmg)

    // Verify code signature
    let verify = Process()
    verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    verify.arguments = ["--verify", "--deep", "--strict", appPath]
    verify.standardOutput = FileHandle.nullDevice
    verify.standardError = FileHandle.nullDevice
    try? verify.run()
    verify.waitUntilExit()

    if verify.terminationStatus != 0 {
        fputs("Warning: \(appName).app failed code signature verification.\n", stderr)
        try? FileManager.default.removeItem(atPath: appPath)
        fputs("Removed unsigned app for safety.\n", stderr)
        exit(1)
    }

    fputs("\(appName) installed (signature verified).\n", stderr)
}

private func configurePipit() {
    fputs("Configuring \(appName) defaults...\n", stderr)

    let defaults: [(String, String, String)] = [
        // Launch at startup
        ("-bool", "LaunchAtStartup", "true"),
        // Hide dock icon — run from menu bar only
        ("-bool", "HideDockIcon", "true"),
        // Show menu bar icon
        ("-bool", "ShowMenuBarIcon", "true"),
        // Disable sound effects
        ("-bool", "EnableSoundEffects", "false"),
        // Multi-language mode (supports Russian + English)
        ("-string", "LanguageMode", "multiLanguage"),
        // Use Parakeet model (supports 25 European languages)
        ("-string", "SelectedVoiceModel", "Parakeet TDT 0.6B"),
        // Mark onboarding as completed
        ("-bool", "HasCompletedOnboarding", "true"),
    ]

    for (type, key, value) in defaults {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", pipitDomain, key, type, value]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

private func detach(_ volumePath: String) {
    let detach = Process()
    detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    detach.arguments = ["detach", volumePath, "-quiet"]
    detach.standardOutput = FileHandle.nullDevice
    detach.standardError = FileHandle.nullDevice
    try? detach.run()
    detach.waitUntilExit()
}
