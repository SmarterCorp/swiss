import Foundation

func runSleepCommand(args: [String]) {
    guard let action = args.first else {
        sleepStatus()
        return
    }

    switch action {
    case "off":
        disableSleep()
    case "on":
        enableSleep()
    case "status":
        sleepStatus()
    case "caffeine":
        runCaffeinate()
    case "help", "-h", "--help":
        printSleepUsage()
    default:
        fputs("Unknown sleep subcommand: \(action)\n", stderr)
        printSleepUsage()
        exit(1)
    }
}

private func printSleepUsage() {
    print("Usage: swiss sleep <command>")
    print("")
    print("Commands:")
    print("  off       — disable sleep (keeps running with lid closed)")
    print("  on        — re-enable sleep (normal behavior)")
    print("  status    — show current sleep state")
    print("  caffeine  — prevent sleep until Ctrl+C")
}

private func disableSleep() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["pmset", "disablesleep", "1"]
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        print("Sleep disabled. Mac will stay awake with lid closed.")
        print("Run 'swiss sleep on' to re-enable.")
    } else {
        fputs("Error: Failed to disable sleep (needs sudo).\n", stderr)
        exit(1)
    }
}

private func enableSleep() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["pmset", "disablesleep", "0"]
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        print("Sleep enabled. Normal behavior restored.")
    } else {
        fputs("Error: Failed to enable sleep (needs sudo).\n", stderr)
        exit(1)
    }
}

private func sleepStatus() {
    // Check disablesleep
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g"]
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

    let output = String(data: data, encoding: .utf8) ?? ""

    let sleepDisabled = output.contains("disablesleep\t\t1") || output.contains("disablesleep             1")

    if sleepDisabled {
        print("Sleep: DISABLED (mac stays awake with lid closed)")
        print("  Run 'swiss sleep on' to re-enable")
    } else {
        print("Sleep: enabled (normal behavior)")
    }

    // Check caffeinate processes
    let pgrep = Process()
    let pgrepPipe = Pipe()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-l", "caffeinate"]
    pgrep.standardOutput = pgrepPipe
    pgrep.standardError = FileHandle.nullDevice
    try? pgrep.run()

    var pgrepData = Data()
    let pgrepGroup = DispatchGroup()
    pgrepGroup.enter()
    DispatchQueue.global().async {
        pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
        pgrepGroup.leave()
    }
    pgrep.waitUntilExit()
    pgrepGroup.wait()

    let pgrepOutput = String(data: pgrepData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !pgrepOutput.isEmpty {
        let count = pgrepOutput.components(separatedBy: "\n").count
        print("Caffeinate: \(count) process(es) active")
    }
}

private func runCaffeinate() -> Never {
    print("Preventing sleep until Ctrl+C...")
    let args = ["caffeinate", "-dimsu"]
    let argv = args.map { strdup($0) } + [nil]
    execvp("caffeinate", argv)
    perror("Failed to exec caffeinate")
    exit(1)
}
