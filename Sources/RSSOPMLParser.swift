import Foundation

struct RSSOPMLParser {
    static func parse(atPath path: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: path) else {
            fputs("Error: cannot read OPML file: \(path)\n", stderr)
            return []
        }
        let delegate = OPMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.feedURLs
    }
}

private class OPMLDelegate: NSObject, XMLParserDelegate {
    var feedURLs: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "outline", let url = attributeDict["xmlUrl"], !url.isEmpty {
            feedURLs.append(url)
        }
    }
}
