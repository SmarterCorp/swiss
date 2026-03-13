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
        fputs("[\(i + 1)/\(total)] \(label)... ", stderr)

        guard let xml = fetchURL(url) else {
            fputs("fetch failed, skipping.\n", stderr)
            continue
        }

        let titles = extractTagTexts(from: xml, tag: "title")
        let uncached = titles.filter { !isCached(text: $0) }
        fputs("\(titles.count) titles, \(uncached.count) to translate\n", stderr)

        // Batch translate all uncached titles in one Ollama call
        if !uncached.isEmpty {
            let batch = batchTranslate(texts: uncached)
            for (original, translated) in zip(uncached, batch) {
                cacheTranslation(original: original, translated: translated)
            }
        }

        // Replace titles in XML with cached translations
        let translated = replaceTagTexts(in: xml, tag: "title")
        let feedFile = tmpDir + "/feed-\(i).xml"
        try? translated.write(toFile: feedFile, atomically: true, encoding: .utf8)

        // Newsboat exec: format — wrap in a script to avoid space/arg issues
        let scriptFile = tmpDir + "/read-\(i).sh"
        try? "#!/bin/sh\ncat '\(feedFile)'\n".write(toFile: scriptFile, atomically: true, encoding: .utf8)
        chmod(scriptFile)
        urlsLines.append("exec:\(scriptFile) \"~\(label)\"")
    }

    fputs("Done.\n", stderr)

    let urlsFile = tmpDir + "/urls"
    try? urlsLines.joined(separator: "\n").write(toFile: urlsFile, atomically: true, encoding: .utf8)
    return urlsFile
}

// MARK: - Feed fetching

private func fetchURL(_ url: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["-s", "-L", "--max-time", "15", "-A", "swiss/1.0", url]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()

    // Read stdout in background to avoid pipe buffer deadlock
    var data = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    process.waitUntilExit()
    group.wait()

    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}

// MARK: - XML tag extraction and replacement

private func extractTagTexts(from xml: String, tag: String) -> [String] {
    let escapedTag = NSRegularExpression.escapedPattern(for: tag)
    let pattern = "<\(escapedTag)[^>]*>(?:<\\!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</\(escapedTag)>"

    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return []
    }

    let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
    return matches.compactMap { match -> String? in
        guard let range = Range(match.range(at: 1), in: xml) else { return nil }
        let text = stripHTML(String(xml[range])).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 3 ? text : nil
    }
}

private func replaceTagTexts(in xml: String, tag: String) -> String {
    let escapedTag = NSRegularExpression.escapedPattern(for: tag)
    let pattern = "(<\(escapedTag)[^>]*>)(?:<\\!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?(</\(escapedTag)>)"

    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return xml
    }

    var result = xml
    let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

    for match in matches.reversed() {
        guard let contentRange = Range(match.range(at: 2), in: result),
              let fullRange = Range(match.range, in: result) else { continue }

        let original = stripHTML(String(result[contentRange])).trimmingCharacters(in: .whitespacesAndNewlines)
        guard original.count > 3 else { continue }

        if let translated = getCached(text: original) {
            let openTag = String(result[Range(match.range(at: 1), in: result)!])
            let closeTag = String(result[Range(match.range(at: 3), in: result)!])
            result.replaceSubrange(fullRange, with: "\(openTag)\(translated)\(closeTag)")
        }
    }

    return result
}

// MARK: - Batch translation (one Ollama call for multiple titles)

private func batchTranslate(texts: [String]) -> [String] {
    let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    let prompt = """
        Translate each numbered line from English to Russian. Keep the numbering. Output only the translations, one per line, with the same numbers. No explanations.

        \(numbered)
        """

    let response = translateText(prompt)

    // Parse numbered response lines
    var results: [String] = []
    let lines = response.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    for i in 0..<texts.count {
        let prefix = "\(i + 1)."
        if let line = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) {
            let translated = line.trimmingCharacters(in: .whitespaces)
                .dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            results.append(translated)
        } else if i < lines.count {
            // Fallback: use line by position
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            // Strip any numbering prefix
            if let dotIndex = line.firstIndex(of: "."), line[line.startIndex..<dotIndex].allSatisfy({ $0.isNumber }) {
                results.append(String(line[line.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces))
            } else {
                results.append(line)
            }
        } else {
            results.append(texts[i]) // fallback to original
        }
    }

    return results
}

// MARK: - Cache

private func cacheKey(for text: String) -> String {
    var hash: UInt64 = 5381
    for byte in text.utf8 {
        hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
    }
    return String(hash, radix: 16)
}

private func isCached(text: String) -> Bool {
    FileManager.default.fileExists(atPath: cacheDir + "/\(cacheKey(for: text)).txt")
}

private func getCached(text: String) -> String? {
    try? String(contentsOfFile: cacheDir + "/\(cacheKey(for: text)).txt", encoding: .utf8)
}

private func cacheTranslation(original: String, translated: String) {
    try? translated.write(toFile: cacheDir + "/\(cacheKey(for: original)).txt", atomically: true, encoding: .utf8)
}

// MARK: - Helpers

private func chmod(_ path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/chmod")
    process.arguments = ["+x", path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

// MARK: - HTML stripping

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
