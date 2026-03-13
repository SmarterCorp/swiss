import Foundation

private let appName = "Pipit"
private let appPath = "/Applications/\(appName).app"
private let dmgURL = "https://github.com/pxkan/Pipit-Releases/releases/download/v1.2.5/Pipit-1.2.5.dmg"

func runVoiceCommand() {
    if !FileManager.default.fileExists(atPath: appPath) {
        installPipit()
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
    fputs("\(appName) installed.\n", stderr)
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
