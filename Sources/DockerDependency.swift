import Foundation

private func dockerPath() -> String? {
    for candidate in [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ] {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

private func isDockerRunning(docker: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: docker)
    process.arguments = ["info"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

private func installDocker() {
    guard let brew = findBrewPath() else {
        fputs("Error: Docker is not installed and Homebrew was not found.\n", stderr)
        fputs("Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/\n", stderr)
        fputs("Or install Homebrew (https://brew.sh) and re-run this command.\n", stderr)
        exit(1)
    }

    fputs("Installing Docker via Homebrew (cask)...\n", stderr)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: brew)
    process.arguments = ["install", "--cask", "docker"]
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fputs("Error: Failed to install Docker via Homebrew.\n", stderr)
        exit(1)
    }

    fputs("Docker installed. Opening Docker Desktop...\n", stderr)
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "Docker"]
    try? open.run()
    open.waitUntilExit()

    fputs("Waiting for Docker to start...\n", stderr)
    waitForDocker()
}

private func waitForDocker() {
    guard let docker = dockerPath() else {
        fputs("Error: Docker binary not found after installation.\n", stderr)
        exit(1)
    }
    for i in 1...30 {
        if isDockerRunning(docker: docker) {
            return
        }
        fputs("  Waiting for Docker daemon... (\(i)/30)\n", stderr)
        Thread.sleep(forTimeInterval: 2)
    }
    fputs("Error: Docker daemon did not start in time. Open Docker Desktop manually and retry.\n", stderr)
    exit(1)
}

func ensureDockerReady() -> String {
    guard let docker = dockerPath() else {
        installDocker()
        guard let docker = dockerPath() else {
            fputs("Error: Docker not found after installation.\n", stderr)
            exit(1)
        }
        return docker
    }

    if !isDockerRunning(docker: docker) {
        fputs("Docker is installed but not running. Starting Docker Desktop...\n", stderr)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Docker"]
        try? open.run()
        open.waitUntilExit()
        waitForDocker()
    }

    return docker
}

func ensureContainer(docker: String, name: String, image: String, ports: String, envVars: [String: String] = [:]) {
    // Check if container exists
    let inspect = Process()
    let inspectPipe = Pipe()
    inspect.executableURL = URL(fileURLWithPath: docker)
    inspect.arguments = ["inspect", "--format", "{{.State.Running}}", name]
    inspect.standardOutput = inspectPipe
    inspect.standardError = FileHandle.nullDevice
    try? inspect.run()

    var inspectData = Data()
    let inspectGroup = DispatchGroup()
    inspectGroup.enter()
    DispatchQueue.global().async {
        inspectData = inspectPipe.fileHandleForReading.readDataToEndOfFile()
        inspectGroup.leave()
    }
    inspect.waitUntilExit()
    inspectGroup.wait()

    if inspect.terminationStatus == 0 {
        let output = String(data: inspectData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if output == "true" {
            // If env vars changed, recreate the container
            if !envVars.isEmpty && containerEnvChanged(docker: docker, name: name, envVars: envVars) {
                fputs("Configuration changed. Recreating \(name) container...\n", stderr)
                stopAndRemoveContainer(docker: docker, name: name)
            } else {
                return // already running with correct config
            }
        } else {
            // Container exists but stopped — remove it if env changed, otherwise start
            if !envVars.isEmpty && containerEnvChanged(docker: docker, name: name, envVars: envVars) {
                stopAndRemoveContainer(docker: docker, name: name)
            } else {
                fputs("Starting \(name) container...\n", stderr)
                let start = Process()
                start.executableURL = URL(fileURLWithPath: docker)
                start.arguments = ["start", name]
                start.standardOutput = FileHandle.nullDevice
                try? start.run()
                start.waitUntilExit()
                if start.terminationStatus == 0 {
                    waitForHTTP(port: ports.components(separatedBy: ":").first ?? "1200")
                    return
                }
            }
        }
    }

    // Container doesn't exist — create and run
    fputs("Pulling and starting \(image)...\n", stderr)
    var args = ["run", "-d", "--name", name, "-p", ports, "--restart", "unless-stopped"]
    for (key, value) in envVars {
        args += ["-e", "\(key)=\(value)"]
    }
    args.append(image)

    let run = Process()
    run.executableURL = URL(fileURLWithPath: docker)
    run.arguments = args
    try? run.run()
    run.waitUntilExit()

    if run.terminationStatus != 0 {
        fputs("Error: Failed to start \(name) container.\n", stderr)
        exit(1)
    }

    let port = ports.components(separatedBy: ":").first ?? "1200"
    waitForHTTP(port: port)
}

private func stopAndRemoveContainer(docker: String, name: String) {
    let stop = Process()
    stop.executableURL = URL(fileURLWithPath: docker)
    stop.arguments = ["rm", "-f", name]
    stop.standardOutput = FileHandle.nullDevice
    stop.standardError = FileHandle.nullDevice
    try? stop.run()
    stop.waitUntilExit()
}

private func containerEnvChanged(docker: String, name: String, envVars: [String: String]) -> Bool {
    let inspect = Process()
    let pipe = Pipe()
    inspect.executableURL = URL(fileURLWithPath: docker)
    inspect.arguments = ["inspect", "--format", "{{range .Config.Env}}{{println .}}{{end}}", name]
    inspect.standardOutput = pipe
    inspect.standardError = FileHandle.nullDevice
    try? inspect.run()

    var data = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    inspect.waitUntilExit()
    group.wait()

    let currentEnv = String(data: data, encoding: .utf8) ?? ""

    for (key, value) in envVars {
        if !currentEnv.contains("\(key)=\(value)") {
            return true
        }
    }
    return false
}

private func waitForHTTP(port: String) {
    fputs("Waiting for service on port \(port)...\n", stderr)
    for _ in 1...15 {
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:\(port)/"]
        let pipe = Pipe()
        curl.standardOutput = pipe
        curl.standardError = FileHandle.nullDevice
        try? curl.run()

        var data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        curl.waitUntilExit()
        group.wait()
        let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if code == "200" || code == "302" || code == "301" {
            fputs("Service is ready.\n", stderr)
            return
        }
        Thread.sleep(forTimeInterval: 2)
    }
    fputs("Warning: Service may not be ready yet, proceeding anyway...\n", stderr)
}
