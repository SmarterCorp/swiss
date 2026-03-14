import Foundation

private let espansoConfigDir = NSHomeDirectory() + "/Library/Application Support/espanso"
private let swissMatchFile = espansoConfigDir + "/match/swiss.yml"

func runPromptCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "espanso", binary: "espanso")])

    guard let action = args.first else {
        printPromptUsage()
        exit(1)
    }

    switch action {
    case "add":
        guard args.count >= 3 else {
            fputs("Usage: swiss prompt add <trigger> <text>\n", stderr)
            fputs("Example: swiss prompt add :addr 123 Main St, City\n", stderr)
            exit(1)
        }
        let trigger = normalizeTrigger(args[1])
        let text = args.dropFirst(2).joined(separator: " ")
        addPrompt(trigger: trigger, text: text)
    case "remove", "delete", "rm":
        guard args.count >= 2 else {
            fputs("Usage: swiss prompt remove <trigger>\n", stderr)
            exit(1)
        }
        let trigger = normalizeTrigger(args[1])
        removePrompt(trigger: trigger)
    case "list", "ls":
        listPrompts()
    case "start":
        startEspanso()
    case "stop":
        stopEspanso()
    case "status":
        statusEspanso()
    default:
        fputs("Unknown prompt subcommand: \(action)\n", stderr)
        printPromptUsage()
        exit(1)
    }
}

private func printPromptUsage() {
    print("Usage: swiss prompt <command>")
    print("")
    print("Commands:")
    print("  add <trigger> <text>  — add a text expansion (e.g. swiss prompt add :addr 123 Main St)")
    print("  remove <trigger>      — remove a text expansion")
    print("  list                  — list all expansions")
    print("  start                 — start the Espanso daemon")
    print("  stop                  — stop the Espanso daemon")
    print("  status                — check if Espanso is running")
}

// MARK: - Trigger normalization

private func normalizeTrigger(_ input: String) -> String {
    input.hasPrefix(":") ? input : ":\(input)"
}

// MARK: - YAML match file management

private struct Match {
    let trigger: String
    let replace: String
}

private func readMatches() -> [Match] {
    guard let content = try? String(contentsOfFile: swissMatchFile, encoding: .utf8) else {
        return []
    }

    var matches: [Match] = []
    let lines = content.components(separatedBy: "\n")
    var i = 0
    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("- trigger:") {
            let trigger = extractYAMLValue(line.replacingOccurrences(of: "- trigger:", with: "trigger:"), key: "trigger")
            if i + 1 < lines.count {
                let replaceLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if replaceLine.hasPrefix("replace:") {
                    let replace = extractYAMLValue(replaceLine, key: "replace")
                    matches.append(Match(trigger: trigger, replace: replace))
                }
            }
            i += 2
        } else {
            i += 1
        }
    }
    return matches
}

private func writeMatches(_ matches: [Match]) {
    var lines: [String] = ["matches:"]
    for match in matches {
        let escapedReplace = match.replace
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        lines.append("  - trigger: \"\(match.trigger)\"")
        lines.append("    replace: \"\(escapedReplace)\"")
    }
    let content = lines.joined(separator: "\n") + "\n"
    try? content.write(toFile: swissMatchFile, atomically: true, encoding: .utf8)
}

private func extractYAMLValue(_ line: String, key: String) -> String {
    let raw = line.replacingOccurrences(of: "\(key):", with: "").trimmingCharacters(in: .whitespaces)
    // Strip surrounding quotes
    if raw.hasPrefix("\"") && raw.hasSuffix("\"") {
        return String(raw.dropFirst().dropLast())
    }
    return raw
}

// MARK: - Add / Remove / List

private func addPrompt(trigger: String, text: String) {
    var matches = readMatches()

    if let idx = matches.firstIndex(where: { $0.trigger == trigger }) {
        matches[idx] = Match(trigger: trigger, replace: text)
        writeMatches(matches)
        print("Updated \(trigger)")
    } else {
        matches.append(Match(trigger: trigger, replace: text))
        writeMatches(matches)
        print("Added \(trigger) -> \(text)")
    }

    reloadEspanso()
}

private func removePrompt(trigger: String) {
    var matches = readMatches()
    let before = matches.count
    matches.removeAll { $0.trigger == trigger }

    if matches.count == before {
        fputs("\(trigger) not found.\n", stderr)
        exit(1)
    }

    writeMatches(matches)
    print("Removed \(trigger)")
    reloadEspanso()
}

private func listPrompts() {
    let matches = readMatches()
    if matches.isEmpty {
        print("No prompts configured. Add one with: swiss prompt add :trigger text")
        return
    }
    let maxTrigger = matches.map { $0.trigger.count }.max() ?? 10
    for match in matches {
        let padded = match.trigger.padding(toLength: maxTrigger, withPad: " ", startingAt: 0)
        let preview = match.replace.count > 60 ? String(match.replace.prefix(60)) + "..." : match.replace
        print("\(padded)  ->  \(preview)")
    }
}

// MARK: - Espanso daemon control

private func startEspanso() {
    // Register service if not yet registered
    let register = Process()
    register.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    register.arguments = ["espanso", "service", "register"]
    register.standardOutput = FileHandle.nullDevice
    register.standardError = FileHandle.nullDevice
    try? register.run()
    register.waitUntilExit()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["espanso", "start"]
    try? process.run()
    process.waitUntilExit()
}

private func stopEspanso() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["espanso", "stop"]
    try? process.run()
    process.waitUntilExit()
}

private func statusEspanso() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["espanso", "status"]
    try? process.run()
    process.waitUntilExit()
}

private func reloadEspanso() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["espanso", "restart"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}
