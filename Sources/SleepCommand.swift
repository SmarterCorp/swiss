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
    runSudo(["pmset", "disablesleep", "1"])
    print("Sleep disabled. Mac will stay awake with lid closed.")
    print("Run 'swiss sleep on' to re-enable.")
}

private func enableSleep() {
    runSudo(["pmset", "disablesleep", "0"])
    print("Sleep enabled. Normal behavior restored.")
}

private func runSudo(_ command: [String]) {
    // Check if we already have sudo cached
    let check = Process()
    check.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    check.arguments = ["-n", "true"]
    check.standardOutput = FileHandle.nullDevice
    check.standardError = FileHandle.nullDevice
    try? check.run()
    check.waitUntilExit()

    if check.terminationStatus != 0 {
        // Need password — read it securely
        fputs("Password: ", stderr)
        let password = readPassword()

        // Validate password first with sudo -v
        let validate = Process()
        let valPipe = Pipe()
        validate.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        validate.arguments = ["-S", "-v"]
        validate.standardInput = valPipe
        validate.standardError = FileHandle.nullDevice
        try? validate.run()

        // Small delay to let sudo open stdin
        Thread.sleep(forTimeInterval: 0.1)
        valPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
        valPipe.fileHandleForWriting.closeFile()
        validate.waitUntilExit()

        if validate.terminationStatus != 0 {
            fputs("Error: Wrong password.\n", stderr)
            exit(1)
        }

        // Now sudo is cached, run the actual command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = command
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            fputs("Error: Command failed.\n", stderr)
            exit(1)
        }
    } else {
        // Sudo cached — just run
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = command
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            fputs("Error: Command failed.\n", stderr)
            exit(1)
        }
    }
}

private func readPassword() -> String {
    // Disable terminal echo for secure password input
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

    let password = readLine() ?? ""

    // Restore terminal echo
    tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    fputs("\n", stderr)

    return password
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
    let caffeinateCount = pgrepOutput.isEmpty ? 0 : pgrepOutput.components(separatedBy: "\n").count

    if jsonMode {
        printJSON(["sleep_disabled": sleepDisabled, "caffeinate_processes": caffeinateCount])
        return
    }

    if sleepDisabled {
        print("Sleep: DISABLED (mac stays awake with lid closed)")
        print("  Run 'swiss sleep on' to re-enable")
    } else {
        print("Sleep: enabled (normal behavior)")
    }

    if caffeinateCount > 0 {
        print("Caffeinate: \(caffeinateCount) process(es) active")
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
