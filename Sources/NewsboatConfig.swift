import Foundation

func newsboatConfigPath() -> String {
    let configDir = NSHomeDirectory() + "/.config/swiss"
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
