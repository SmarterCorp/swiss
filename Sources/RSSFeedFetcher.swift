import Foundation

struct RSSFeedFetcher {
    struct FetchResult {
        let title: String
        let siteURL: String
        let entries: [(guid: String, title: String, url: String, published: String)]
    }

    static func fetch(url: String) -> FetchResult? {
        guard let feedURL = URL(string: url) else { return nil }

        var result: FetchResult?
        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: feedURL) { data, _, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            result = parse(data: data, feedURL: url)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 30)

        return result
    }

    private static func parse(data: Data, feedURL: String) -> FetchResult? {
        let delegate = FeedXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        guard !delegate.entries.isEmpty || !delegate.feedTitle.isEmpty else { return nil }

        return FetchResult(
            title: delegate.feedTitle,
            siteURL: delegate.siteURL,
            entries: delegate.entries.map { e in
                (guid: e.guid.isEmpty ? e.url : e.guid,
                 title: e.title,
                 url: e.url,
                 published: normalizeDate(e.published))
            }
        )
    }

    private static func normalizeDate(_ dateStr: String) -> String {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Try ISO 8601 first (Atom feeds)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) {
            return iso.string(from: date)
        }

        // Try ISO 8601 with fractional seconds
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFrac.date(from: trimmed) {
            return iso.string(from: date)
        }

        // Try RFC 822 (RSS feeds)
        let rfc822Formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in rfc822Formats {
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) {
                return iso.string(from: date)
            }
        }

        return trimmed
    }
}

private class FeedXMLDelegate: NSObject, XMLParserDelegate {
    struct ParsedEntry {
        var title: String = ""
        var url: String = ""
        var guid: String = ""
        var published: String = ""
    }

    var feedTitle: String = ""
    var siteURL: String = ""
    var entries: [ParsedEntry] = []

    private var currentElement: String = ""
    private var currentText: String = ""
    private var inItem = false
    private var inChannel = false
    private var isAtom = false
    private var currentEntry = ParsedEntry()
    private var didSetFeedTitle = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "feed":
            isAtom = true
        case "channel":
            inChannel = true
        case "item", "entry":
            inItem = true
            currentEntry = ParsedEntry()
        case "link":
            if isAtom {
                let rel = attributeDict["rel"] ?? "alternate"
                let href = attributeDict["href"] ?? ""
                if inItem && rel == "alternate" {
                    currentEntry.url = href
                } else if !inItem && rel == "alternate" {
                    siteURL = href
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "item" || elementName == "entry" {
            inItem = false
            entries.append(currentEntry)
            return
        }

        if elementName == "channel" {
            inChannel = false
            return
        }

        if inItem {
            switch elementName {
            case "title":
                currentEntry.title = text
            case "link":
                if !isAtom { currentEntry.url = text }
            case "guid", "id":
                currentEntry.guid = text
            case "pubDate", "published", "updated":
                if currentEntry.published.isEmpty {
                    currentEntry.published = text
                }
            default:
                break
            }
        } else {
            switch elementName {
            case "title":
                if !didSetFeedTitle {
                    feedTitle = text
                    didSetFeedTitle = true
                }
            case "link":
                if !isAtom && siteURL.isEmpty { siteURL = text }
            default:
                break
            }
        }
    }
}
