import Foundation

func runPortsCommand() {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-iTCP", "-sTCP:LISTEN", "-nP", "-Fcpin"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        print("Failed to run lsof: \(error)")
        return
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return }

    struct PortEntry {
        let port: String
        let pid: String
        let process: String
    }

    var entries: [PortEntry] = []
    var seen = Set<String>()
    var currentPid = ""
    var currentProcess = ""

    for line in output.components(separatedBy: "\n") where !line.isEmpty {
        let tag = line.first!
        let value = String(line.dropFirst())

        switch tag {
        case "p":
            currentPid = value
        case "c":
            currentProcess = value
        case "n":
            // format: *:port or host:port
            if let colonRange = value.range(of: ":", options: .backwards) {
                let port = String(value[colonRange.upperBound...])
                let key = "\(port):\(currentPid)"
                if !seen.contains(key) {
                    seen.insert(key)
                    entries.append(PortEntry(port: port, pid: currentPid, process: currentProcess))
                }
            }
        default:
            break
        }
    }

    entries.sort { (Int($0.port) ?? 0) < (Int($1.port) ?? 0) }

    if jsonMode {
        let ports = entries.map { ["port": Int($0.port) ?? 0, "pid": Int($0.pid) ?? 0, "process": $0.process] as [String: Any] }
        printJSON(["ports": ports])
        return
    }

    guard !entries.isEmpty else {
        print("No listening ports found.")
        return
    }

    let portW = max(5, entries.map { $0.port.count }.max() ?? 5)
    let pidW = max(5, entries.map { $0.pid.count }.max() ?? 5)

    print("PORT".padding(toLength: portW, withPad: " ", startingAt: 0) + "  "
        + "PID".padding(toLength: pidW, withPad: " ", startingAt: 0) + "  PROCESS")
    print(String(repeating: "─", count: portW + pidW + 12))
    for e in entries {
        print(e.port.padding(toLength: portW, withPad: " ", startingAt: 0) + "  "
            + e.pid.padding(toLength: pidW, withPad: " ", startingAt: 0) + "  " + e.process)
    }
}
