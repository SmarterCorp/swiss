import Foundation

func runStatusCommand() {
    // Cursor teleporter
    let cursorPid = NSString("~/.swiss-cursor.pid").expandingTildeInPath
    var cursorRunning = false
    var cursorPidValue: Int32 = 0
    if let pidStr = try? String(contentsOfFile: cursorPid, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = Int32(pidStr), kill(pid, 0) == 0 {
        cursorRunning = true
        cursorPidValue = pid
    }

    // Espanso
    let espansoRunning = checkProcess("espanso", args: ["status"], expect: "running")

    // Ollama
    let ollamaRunning = checkHTTP(port: "11434")

    // Docker
    let dockerRunning = checkCommand("/usr/bin/env", args: ["docker", "info"])

    // RSSHub container
    let rsshubRunning = dockerRunning ? checkDockerContainer("rsshub") : false

    // Pipit
    let pipitRunning = checkCommand("/usr/bin/pgrep", args: ["-x", "Pipit"])

    if jsonMode {
        let services: [[String: Any]] = [
            ["name": "cursor", "running": cursorRunning],
            ["name": "espanso", "running": espansoRunning],
            ["name": "ollama", "running": ollamaRunning],
            ["name": "docker", "running": dockerRunning],
            ["name": "rsshub", "running": rsshubRunning],
            ["name": "pipit", "running": pipitRunning],
        ]
        printJSON(["services": services])
        return
    }

    print("swiss services:")
    print("")

    if cursorRunning {
        printStatus("cursor", running: true, detail: "PID \(cursorPidValue)")
    } else {
        printStatus("cursor", running: false)
    }

    printStatus("prompt (espanso)", running: espansoRunning)
    printStatus("ollama", running: ollamaRunning, detail: ollamaRunning ? "localhost:11434" : nil)
    printStatus("docker", running: dockerRunning)

    if dockerRunning {
        printStatus("rsshub", running: rsshubRunning, detail: rsshubRunning ? "localhost:1200" : nil)
    } else {
        printStatus("rsshub", running: false, detail: "docker not running")
    }

    printStatus("voice (pipit)", running: pipitRunning)
}

private func printStatus(_ name: String, running: Bool, detail: String? = nil) {
    let icon = running ? "+" : "-"
    let state = running ? "running" : "stopped"
    let padded = name.padding(toLength: 18, withPad: " ", startingAt: 0)
    if let detail = detail {
        print("  [\(icon)] \(padded) \(state)  (\(detail))")
    } else {
        print("  [\(icon)] \(padded) \(state)")
    }
}

private func checkProcess(_ binary: String, args: [String], expect: String) -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [binary] + args
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
    return output.contains(expect)
}

private func checkCommand(_ path: String, args: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func checkHTTP(port: String) -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "2", "http://localhost:\(port)/"]
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

    let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return code == "200" || code == "301" || code == "302"
}

private func checkDockerContainer(_ name: String) -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["docker", "inspect", "--format", "{{.State.Running}}", name]
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

    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return output == "true"
}
