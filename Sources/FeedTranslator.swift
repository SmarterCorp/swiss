import Foundation

private let cacheDir = NSHomeDirectory() + "/.cache/swiss/translated"

func translateFeeds(urls: [String], labels: [String]) -> String {
    ensureOllamaReady()

    let fm = FileManager.default
    try? fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

    let tmpDir = NSTemporaryDirectory() + "swiss-translated"
    try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

    var urlsLines: [String] = []
    let total = urls.count

    for (i, url) in urls.enumerated() {
        let label = i < labels.count ? labels[i] : "Feed \(i + 1)"
        fputs("Translating [\(i + 1)/\(total)] \(label)...\n", stderr)

        guard let xml = fetchURL(url) else {
            fputs("  Failed to fetch, skipping.\n", stderr)
            continue
        }

        let translated = translateFeedXML(xml)
        let feedFile = tmpDir + "/feed-\(i).xml"
        try? translated.write(toFile: feedFile, atomically: true, encoding: .utf8)

        urlsLines.append("file://\(feedFile) \"\(label)\"")
    }

    let urlsFile = tmpDir + "/urls"
    try? urlsLines.joined(separator: "\n").write(toFile: urlsFile, atomically: true, encoding: .utf8)
    return urlsFile
}

private func fetchURL(_ url: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["-s", "-L", "--max-time", "15", url]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

private func translateFeedXML(_ xml: String) -> String {
    var result = xml

    // Translate <title>...</title> inside <item> or <entry> blocks
    result = translateTagContent(in: result, tag: "title")
    // Translate <description>...</description>
    result = translateTagContent(in: result, tag: "description")
    // Translate <content:encoded>...</content:encoded> (common in RSS)
    result = translateTagContent(in: result, tag: "content:encoded")
    // Translate <summary>...</summary> (Atom feeds)
    result = translateTagContent(in: result, tag: "summary")

    return result
}

private func translateTagContent(in xml: String, tag: String) -> String {
    let escapedTag = NSRegularExpression.escapedPattern(for: tag)
    let pattern = "(<\(escapedTag)[^>]*>)(<\\!\\[CDATA\\[)?(.*?)(\\]\\]>)?(</\(escapedTag)>)"

    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return xml
    }

    var result = xml
    let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

    // Process in reverse to preserve ranges
    for match in matches.reversed() {
        guard match.numberOfRanges >= 6 else { continue }

        let contentRange = match.range(at: 3)
        guard contentRange.location != NSNotFound,
              let swiftRange = Range(contentRange, in: result) else { continue }

        let content = String(result[swiftRange])
        let stripped = stripHTML(content).trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty, very short, or already non-English content
        guard stripped.count > 5 else { continue }

        // Check cache
        let cacheKey = stableHash(stripped)
        let cachePath = cacheDir + "/\(cacheKey).txt"

        let translated: String
        if let cached = try? String(contentsOfFile: cachePath, encoding: .utf8) {
            translated = cached
        } else {
            translated = translateText(stripped)
            try? translated.write(toFile: cachePath, atomically: true, encoding: .utf8)
        }

        result = result.replacingCharacters(in: swiftRange, with: translated)
    }

    return result
}

private func stripHTML(_ html: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
        return html
    }
    let range = NSRange(html.startIndex..., in: html)
    return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")
}

private func stableHash(_ string: String) -> String {
    // Simple hash for cache keys
    var hash: UInt64 = 5381
    for byte in string.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return String(hash, radix: 16)
}
