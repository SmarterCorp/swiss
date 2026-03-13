import Foundation

func runRSSCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "newsboat", binary: "newsboat")])

    let dir = NSHomeDirectory() + "/.newsboat"
    let urlsFile = dir + "/urls"
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir) {
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: urlsFile) {
        fm.createFile(atPath: urlsFile, contents: nil)
    }

    let translateMode = args.contains("-ru")
    let filteredArgs = args.filter { $0 != "-ru" }

    var newsboatArgs = ["newsboat", "-C", newsboatConfigPath()]

    if translateMode {
        // Read feed URLs from urls file, translate them
        if let content = try? String(contentsOfFile: urlsFile, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
            let feedUrls = lines.map { $0.components(separatedBy: " ").first ?? "" }
            let labels = lines.map { line -> String in
                if let start = line.range(of: "\"~"), let end = line.range(of: "\"", range: line.index(start.upperBound, offsetBy: 0)..<line.endIndex) {
                    return String(line[start.upperBound..<end.lowerBound])
                }
                return line.components(separatedBy: " ").first ?? "Feed"
            }
            let translatedUrls = translateFeeds(urls: feedUrls, labels: labels)
            newsboatArgs += ["-u", translatedUrls, "-r"]
        }
        newsboatArgs += filteredArgs
    } else {
        newsboatArgs += filteredArgs
    }

    let argv = newsboatArgs.map { strdup($0) } + [nil]
    execvp("newsboat", argv)

    perror("Failed to exec newsboat")
    exit(1)
}
