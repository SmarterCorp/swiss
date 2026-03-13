import Foundation

let swissConfigDir = NSHomeDirectory() + "/.config/swiss"

func extractFeedLabel(from line: String) -> String {
    if let start = line.range(of: "\"~"),
       let end = line.range(of: "\"", range: line.index(start.upperBound, offsetBy: 0)..<line.endIndex) {
        return String(line[start.upperBound..<end.lowerBound])
    }
    return line.components(separatedBy: " ").first ?? "Feed"
}

func newsboatConfigPath() -> String {
    let configDir = swissConfigDir
    let configPath = configDir + "/newsboat-config"

    let fm = FileManager.default
    try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)

    var lines: [String] = []

    // Include user's existing newsboat config
    let userConfig = NSHomeDirectory() + "/.newsboat/config"
    if fm.fileExists(atPath: userConfig) {
        lines.append("include \"\(userConfig)\"")
        lines.append("")
    }

    // Translation: press , then t to translate current article to Russian
    lines.append("# swiss: translate article to Russian (press ,t)")
    lines.append("macro t pipe-to \"swiss translate\" -- \"Translate to Russian\"")

    let content = lines.joined(separator: "\n") + "\n"
    try? content.write(toFile: configPath, atomically: true, encoding: .utf8)

    return configPath
}
