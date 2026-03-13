import Foundation

private let ollamaModel = "gemma3"
private let ollamaAPI = "http://localhost:11434/api/generate"

func runTranslateCommand(args: [String]) {
    ensureOllamaReady()

    let text = readInputText(args: args)
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fputs("No text to translate.\n", stderr)
        exit(1)
    }

    let translation = translateText(text)
    print(translation, terminator: "")
}

private func readInputText(args: [String]) -> String {
    if !args.isEmpty {
        // Check if first arg is a readable file
        if args.count == 1 && FileManager.default.isReadableFile(atPath: args[0]) {
            if let content = try? String(contentsOfFile: args[0], encoding: .utf8) {
                return content
            }
        }
        return args.joined(separator: " ")
    }

    // Read from stdin
    if isatty(STDIN_FILENO) == 0 {
        if let data = Optional(FileHandle.standardInput.readDataToEndOfFile()),
           let content = String(data: data, encoding: .utf8) {
            return content
        }
    }

    fputs("Usage: swiss translate <text>\n", stderr)
    fputs("       swiss translate <file>\n", stderr)
    fputs("       cat file | swiss translate\n", stderr)
    exit(1)
}

func ensureOllamaReady() {
    ensureBrewDependencies([BrewDependency(package: "ollama", binary: "ollama")])

    if !isOllamaRunning() {
        fputs("Starting Ollama...\n", stderr)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ollama", "serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Don't wait — it runs as a server

        for i in 1...15 {
            if isOllamaRunning() { break }
            if i == 15 {
                fputs("Error: Ollama did not start. Run 'ollama serve' manually.\n", stderr)
                exit(1)
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    ensureModelPulled()
}

private func isOllamaRunning() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:11434/api/tags"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return code == "200"
}

private func ensureModelPulled() {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["ollama", "list"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    if output.contains(ollamaModel) {
        return
    }

    fputs("Pulling \(ollamaModel) model (first time only)...\n", stderr)
    let pull = Process()
    pull.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    pull.arguments = ["ollama", "pull", ollamaModel]
    pull.standardError = FileHandle.standardError
    try? pull.run()
    pull.waitUntilExit()

    if pull.terminationStatus != 0 {
        fputs("Error: Failed to pull \(ollamaModel) model.\n", stderr)
        exit(1)
    }
}

func translateText(_ text: String) -> String {
    let prompt = "Translate the following English text to Russian. Output only the translation, nothing else.\n\n\(text)"

    // Build JSON payload
    let escaped = prompt
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    let json = "{\"model\":\"\(ollamaModel)\",\"prompt\":\"\(escaped)\",\"stream\":false}"

    let process = Process()
    let outPipe = Pipe()
    let inPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = [
        "-s", "-X", "POST", ollamaAPI,
        "-H", "Content-Type: application/json",
        "-d", "@-",
    ]
    process.standardInput = inPipe
    process.standardOutput = outPipe
    process.standardError = FileHandle.nullDevice
    try? process.run()

    inPipe.fileHandleForWriting.write(json.data(using: .utf8)!)
    inPipe.fileHandleForWriting.closeFile()
    process.waitUntilExit()

    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    guard let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = responseJSON["response"] as? String else {
        fputs("Error: Failed to parse Ollama response.\n", stderr)
        if let raw = String(data: data, encoding: .utf8) {
            fputs("Raw response: \(raw)\n", stderr)
        }
        exit(1)
    }

    return response
}
