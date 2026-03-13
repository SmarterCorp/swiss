import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

class RSSTUI {
    private let db: RSSDatabase
    private var feeds: [RSSFeed] = []
    private var entries: [RSSEntry] = []
    private var feedIndex = 0
    private var entryIndex = 0
    private var activePane: Pane = .feeds
    private var termWidth: Int = 80
    private var termHeight: Int = 24
    private var running = true
    private var statusMessage: String = ""
    private var originalTermios = termios()
    private let feedPaneWidth = 28

    enum Pane { case feeds, entries }

    init(db: RSSDatabase) {
        self.db = db
    }

    func run() {
        setupTerminal()
        setupSignals()
        refreshData()
        fetchAllFeeds()
        refreshData()

        while running {
            render()
            handleInput()
        }

        restoreTerminal()
    }

    // MARK: - Terminal setup

    private func setupTerminal() {
        // Save and set raw mode
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~UInt(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~UInt(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~UInt(OPOST)
        raw.c_cc.16 = 0  // VMIN
        raw.c_cc.17 = 1  // VTIME (100ms)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        // Alternate screen buffer, hide cursor
        write(STDOUT_FILENO, "\u{1b}[?1049h\u{1b}[?25l", 18)

        updateTermSize()
    }

    private func restoreTerminal() {
        // Show cursor, restore screen
        write(STDOUT_FILENO, "\u{1b}[?25h\u{1b}[?1049l", 18)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }

    private func setupSignals() {
        signal(SIGWINCH) { _ in
            // handled in render loop
        }
        signal(SIGINT) { _ in
            // Restore terminal on Ctrl+C
            var orig = termios()
            tcgetattr(STDIN_FILENO, &orig)
            write(STDOUT_FILENO, "\u{1b}[?25h\u{1b}[?1049l", 18)
            exit(0)
        }
    }

    private func updateTermSize() {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 {
            termWidth = Int(ws.ws_col)
            termHeight = Int(ws.ws_row)
        }
    }

    // MARK: - Data

    private func refreshData() {
        feeds = db.allFeeds()
        loadEntries()
    }

    private func loadEntries() {
        if feedIndex == 0 {
            entries = db.allEntries()
        } else {
            let fi = feedIndex - 1
            if fi < feeds.count {
                entries = db.entriesForFeed(id: feeds[fi].id)
            } else {
                entries = []
            }
        }
        if entryIndex >= entries.count {
            entryIndex = max(0, entries.count - 1)
        }
    }

    private func fetchAllFeeds() {
        statusMessage = "Fetching feeds..."
        render()

        let allFeeds = db.allFeeds()
        for feed in allFeeds {
            if let result = RSSFeedFetcher.fetch(url: feed.url) {
                let title = result.title.isEmpty ? feed.url : result.title
                db.updateFeedMeta(id: feed.id, title: title, siteURL: result.siteURL)
                db.upsertEntries(result.entries, feedId: feed.id)
            }
        }
        statusMessage = "Fetched \(allFeeds.count) feed(s)"
    }

    // MARK: - Rendering

    private func render() {
        updateTermSize()

        var buf = "\u{1b}[H" // cursor home

        let contentHeight = termHeight - 3 // top border + bottom bar + bottom border
        let entryPaneWidth = termWidth - feedPaneWidth - 3 // borders

        // Top border
        buf += "\u{1b}[36m"
        buf += "┌─ Feeds "
        buf += String(repeating: "─", count: max(0, feedPaneWidth - 8))
        buf += "┬─ Entries "
        buf += String(repeating: "─", count: max(0, entryPaneWidth - 9))
        buf += "┐"
        buf += "\u{1b}[0m"
        buf += "\u{1b}[K\r\n"

        // Feed items: "All" + each feed
        let feedItems = buildFeedItems()
        let entryItems = buildEntryItems(width: entryPaneWidth)

        let feedScroll = scrollOffset(selected: feedIndex, count: feedItems.count, height: contentHeight)
        let entryScroll = scrollOffset(selected: entryIndex, count: entryItems.count, height: contentHeight)

        for row in 0..<contentHeight {
            buf += "\u{1b}[36m│\u{1b}[0m"

            // Feed column
            let fi = row + feedScroll
            if fi < feedItems.count {
                let isSelected = fi == feedIndex && activePane == .feeds
                let item = feedItems[fi]
                if isSelected {
                    buf += "\u{1b}[7m"
                }
                buf += padOrTruncate(item, width: feedPaneWidth)
                if isSelected {
                    buf += "\u{1b}[0m"
                }
            } else {
                buf += String(repeating: " ", count: feedPaneWidth)
            }

            buf += "\u{1b}[36m│\u{1b}[0m"

            // Entry column
            let ei = row + entryScroll
            if ei < entryItems.count {
                let entry = ei < entries.count ? entries[ei] : nil
                let isSelected = ei == entryIndex && activePane == .entries
                let isUnread = entry.map { !$0.read } ?? false

                if isSelected {
                    buf += "\u{1b}[7m"
                }
                if isUnread {
                    buf += "\u{1b}[1m"
                }
                buf += padOrTruncate(entryItems[ei], width: entryPaneWidth)
                buf += "\u{1b}[0m"
            } else {
                buf += String(repeating: " ", count: entryPaneWidth)
            }

            buf += "\u{1b}[36m│\u{1b}[0m\u{1b}[K\r\n"
        }

        // Status bar
        buf += "\u{1b}[36m├"
        buf += String(repeating: "─", count: feedPaneWidth + 1)
        buf += "┴"
        buf += String(repeating: "─", count: entryPaneWidth + 1)
        buf += "┤\u{1b}[0m\u{1b}[K\r\n"

        let help = " ↑↓/jk nav  ←→/hl pane  Enter open  r refresh  m read  a all-read  d del  q quit"
        let bar = statusMessage.isEmpty ? help : " \(statusMessage)"
        buf += "\u{1b}[36m│\u{1b}[0m"
        buf += padOrTruncate(bar, width: termWidth - 2)
        buf += "\u{1b}[36m│\u{1b}[0m\u{1b}[K\r\n"

        buf += "\u{1b}[36m└"
        buf += String(repeating: "─", count: termWidth - 2)
        buf += "┘\u{1b}[0m\u{1b}[K"

        // Clear any remaining lines
        buf += "\u{1b}[J"

        let data = Array(buf.utf8)
        data.withUnsafeBufferPointer { ptr in
            _ = write(STDOUT_FILENO, ptr.baseAddress!, data.count)
        }
    }

    private func buildFeedItems() -> [String] {
        var items: [String] = []
        let totalUnread = db.totalUnreadCount()
        let marker = (activePane == .feeds && feedIndex == 0) ? "▶" : " "
        items.append(" \(marker) All (\(totalUnread))")

        for (i, feed) in feeds.enumerated() {
            let m = (activePane == .feeds && feedIndex == i + 1) ? "▶" : " "
            let name = feed.title.isEmpty ? feed.url : feed.title
            items.append(" \(m) \(name) (\(feed.unreadCount))")
        }
        return items
    }

    private func buildEntryItems(width: Int) -> [String] {
        return entries.map { entry in
            let date = formatDate(entry.published)
            let marker = entry.read ? " " : "●"
            let feedLabel = feedIndex == 0 ? "[\(truncate(entry.feedTitle, max: 12))] " : ""
            return " \(marker) \(date)  \(feedLabel)\(entry.title)"
        }
    }

    private func formatDate(_ iso: String) -> String {
        // Extract just the date part from ISO 8601
        if iso.count >= 10 {
            return String(iso.prefix(10))
        }
        return iso.isEmpty ? "          " : iso
    }

    private func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max - 1)) + "…"
    }

    private func padOrTruncate(_ s: String, width: Int) -> String {
        guard width > 0 else { return "" }
        // Count visible characters (strip ANSI codes for length)
        let visible = s.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
        if visible.count >= width {
            // Truncate - need to be careful with ANSI codes
            var result = ""
            var visCount = 0
            var i = s.startIndex
            while i < s.endIndex && visCount < width {
                if s[i] == "\u{1b}" {
                    // Copy entire escape sequence
                    let escStart = i
                    i = s.index(after: i)
                    while i < s.endIndex && s[i] != "m" {
                        i = s.index(after: i)
                    }
                    if i < s.endIndex {
                        i = s.index(after: i)
                    }
                    result += String(s[escStart..<i])
                } else {
                    result.append(s[i])
                    visCount += 1
                    i = s.index(after: i)
                }
            }
            return result
        } else {
            return s + String(repeating: " ", count: width - visible.count)
        }
    }

    private func scrollOffset(selected: Int, count: Int, height: Int) -> Int {
        if count <= height { return 0 }
        let half = height / 2
        if selected < half { return 0 }
        if selected > count - half { return count - height }
        return selected - half
    }

    // MARK: - Input

    private func handleInput() {
        var c: UInt8 = 0
        let n = read(STDIN_FILENO, &c, 1)
        guard n == 1 else { return }

        statusMessage = ""

        switch c {
        case 0x71, 0x1b: // q or Esc
            if c == 0x1b {
                // Check for arrow key sequence
                var seq: [UInt8] = [0, 0]
                let n1 = read(STDIN_FILENO, &seq, 2)
                if n1 == 2 && seq[0] == 0x5b {
                    switch seq[1] {
                    case 0x41: moveUp(); return    // Up
                    case 0x42: moveDown(); return  // Down
                    case 0x43: moveRight(); return // Right
                    case 0x44: moveLeft(); return  // Left
                    default: break
                    }
                }
                running = false
            } else {
                running = false
            }
        case 0x6b: moveUp()      // k
        case 0x6a: moveDown()    // j
        case 0x68: moveLeft()    // h
        case 0x6c: moveRight()   // l
        case 0x0d: enterAction() // Enter
        case 0x72: refreshAction() // r
        case 0x6d: toggleRead()  // m
        case 0x61: markAllRead() // a
        case 0x64: deleteFeed()  // d
        case 0x67: jumpTop()     // g
        case 0x47: jumpBottom()  // G
        default: break
        }
    }

    private func moveUp() {
        if activePane == .feeds {
            feedIndex = max(0, feedIndex - 1)
            entryIndex = 0
            loadEntries()
        } else {
            entryIndex = max(0, entryIndex - 1)
        }
    }

    private func moveDown() {
        if activePane == .feeds {
            feedIndex = min(feeds.count, feedIndex + 1) // count includes "All"
            entryIndex = 0
            loadEntries()
        } else {
            entryIndex = min(max(0, entries.count - 1), entryIndex + 1)
        }
    }

    private func moveLeft() {
        activePane = .feeds
    }

    private func moveRight() {
        if activePane == .feeds {
            activePane = .entries
            entryIndex = 0
        }
    }

    private func enterAction() {
        if activePane == .feeds {
            activePane = .entries
            entryIndex = 0
        } else if entryIndex < entries.count {
            let entry = entries[entryIndex]
            if !entry.url.isEmpty {
                db.markRead(entryId: entry.id)
                entries[entryIndex].read = true
                // Open URL in browser
                restoreTerminal()
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = [entry.url]
                try? proc.run()
                proc.waitUntilExit()
                setupTerminal()
            }
        }
    }

    private func refreshAction() {
        fetchAllFeeds()
        refreshData()
    }

    private func toggleRead() {
        guard activePane == .entries, entryIndex < entries.count else { return }
        let entry = entries[entryIndex]
        let newRead = !entry.read
        db.markRead(entryId: entry.id, read: newRead)
        entries[entryIndex].read = newRead
        feeds = db.allFeeds()
    }

    private func markAllRead() {
        if feedIndex == 0 {
            db.markAllReadGlobal()
        } else {
            let fi = feedIndex - 1
            if fi < feeds.count {
                db.markAllRead(feedId: feeds[fi].id)
            }
        }
        refreshData()
    }

    private func deleteFeed() {
        guard activePane == .feeds, feedIndex > 0 else { return }
        let fi = feedIndex - 1
        if fi < feeds.count {
            db.deleteFeed(id: feeds[fi].id)
            if feedIndex > feeds.count - 1 {
                feedIndex = max(0, feeds.count - 1)
            }
            refreshData()
            statusMessage = "Feed deleted"
        }
    }

    private func jumpTop() {
        if activePane == .feeds {
            feedIndex = 0
            loadEntries()
        } else {
            entryIndex = 0
        }
    }

    private func jumpBottom() {
        if activePane == .feeds {
            feedIndex = feeds.count
            loadEntries()
        } else {
            entryIndex = max(0, entries.count - 1)
        }
    }
}
