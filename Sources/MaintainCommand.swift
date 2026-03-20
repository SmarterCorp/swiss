import Foundation

private let brewPackages = ["newsboat", "ollama", "dua-cli", "bottom"]
private let brewCasks = ["docker", "espanso", "1password-cli"]
private let ollamaModel = "gemma3"
private let rsshubImage = "diygod/rsshub"
private let rsshubContainer = "rsshub"

func runMaintainCommand() {
    var step = 1
    let total = 4

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

