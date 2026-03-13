import Foundation
import SQLite3

class RSSDatabase {
    private var db: OpaquePointer?

    init() {
        let dir = NSHomeDirectory() + "/.swiss"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/rss.db"

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            fputs("Error: cannot open database at \(path)\n", stderr)
            exit(1)
        }

        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA foreign_keys=ON")

        exec("""
            CREATE TABLE IF NOT EXISTS feeds (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                url TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL DEFAULT '',
                site_url TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT ''
            )
            """)

        exec("""
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                feed_id INTEGER NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
                guid TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL DEFAULT '',
                published TEXT NOT NULL DEFAULT '',
                read INTEGER NOT NULL DEFAULT 0,
                UNIQUE(feed_id, guid)
            )
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(err)
            fputs("SQL error: \(msg)\n", stderr)
        }
    }

    @discardableResult
    func addFeed(url: String) -> Int64? {
        let sql = "INSERT OR IGNORE INTO feeds (url) VALUES (?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (url as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_DONE {
            let rowId = sqlite3_last_insert_rowid(db)
            if rowId > 0 { return rowId }
            // Already existed, look it up
            return feedId(forURL: url)
        }
        return nil
    }

    private func feedId(forURL url: String) -> Int64? {
        let sql = "SELECT id FROM feeds WHERE url = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (url as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }

    func allFeeds() -> [RSSFeed] {
        let sql = """
            SELECT f.id, f.url, f.title, f.site_url, f.updated_at,
                   COUNT(CASE WHEN e.read = 0 THEN 1 END) as unread
            FROM feeds f
            LEFT JOIN entries e ON e.feed_id = f.id
            GROUP BY f.id
            ORDER BY f.title COLLATE NOCASE, f.url
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var feeds: [RSSFeed] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            feeds.append(RSSFeed(
                id: sqlite3_column_int64(stmt, 0),
                url: columnText(stmt, 1),
                title: columnText(stmt, 2),
                siteURL: columnText(stmt, 3),
                updatedAt: columnText(stmt, 4),
                unreadCount: Int(sqlite3_column_int(stmt, 5))
            ))
        }
        return feeds
    }

    func deleteFeed(id: Int64) {
        let sql = "DELETE FROM feeds WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func upsertEntries(_ entries: [(guid: String, title: String, url: String, published: String)], feedId: Int64) {
        let sql = "INSERT OR IGNORE INTO entries (feed_id, guid, title, url, published) VALUES (?, ?, ?, ?, ?)"
        exec("BEGIN")
        for entry in entries {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_int64(stmt, 1, feedId)
            sqlite3_bind_text(stmt, 2, (entry.guid as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (entry.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (entry.url as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (entry.published as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        exec("COMMIT")
    }

    func updateFeedMeta(id: Int64, title: String, siteURL: String) {
        let sql = "UPDATE feeds SET title = ?, site_url = ?, updated_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (siteURL as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, id)
        sqlite3_step(stmt)
    }

    func entriesForFeed(id: Int64) -> [RSSEntry] {
        let sql = """
            SELECT e.id, e.feed_id, e.guid, e.title, e.url, e.published, e.read, f.title
            FROM entries e
            JOIN feeds f ON f.id = e.feed_id
            WHERE e.feed_id = ?
            ORDER BY e.published DESC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return readEntries(stmt)
    }

    func allEntries() -> [RSSEntry] {
        let sql = """
            SELECT e.id, e.feed_id, e.guid, e.title, e.url, e.published, e.read, f.title
            FROM entries e
            JOIN feeds f ON f.id = e.feed_id
            ORDER BY e.published DESC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        return readEntries(stmt)
    }

    func markRead(entryId: Int64, read: Bool = true) {
        let sql = "UPDATE entries SET read = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, read ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, entryId)
        sqlite3_step(stmt)
    }

    func markAllRead(feedId: Int64) {
        let sql = "UPDATE entries SET read = 1 WHERE feed_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, feedId)
        sqlite3_step(stmt)
    }

    func markAllReadGlobal() {
        exec("UPDATE entries SET read = 1")
    }

    func totalUnreadCount() -> Int {
        let sql = "SELECT COUNT(*) FROM entries WHERE read = 0"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    // MARK: - Helpers

    private func readEntries(_ stmt: OpaquePointer?) -> [RSSEntry] {
        var entries: [RSSEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            entries.append(RSSEntry(
                id: sqlite3_column_int64(stmt, 0),
                feedId: sqlite3_column_int64(stmt, 1),
                guid: columnText(stmt, 2),
                title: columnText(stmt, 3),
                url: columnText(stmt, 4),
                published: columnText(stmt, 5),
                read: sqlite3_column_int(stmt, 6) != 0,
                feedTitle: columnText(stmt, 7)
            ))
        }
        return entries
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        if let cStr = sqlite3_column_text(stmt, col) {
            return String(cString: cStr)
        }
        return ""
    }
}
