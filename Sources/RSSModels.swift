import Foundation

struct RSSFeed {
    let id: Int64
    let url: String
    var title: String
    var siteURL: String
    var updatedAt: String
    var unreadCount: Int
}

struct RSSEntry {
    let id: Int64
    let feedId: Int64
    let guid: String
    let title: String
    let url: String
    let published: String
    var read: Bool
    var feedTitle: String = ""
}
