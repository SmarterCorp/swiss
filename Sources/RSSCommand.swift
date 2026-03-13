import Foundation

func runRSSCommand(args: [String]) {
    let db = RSSDatabase()

    if let sub = args.first {
        switch sub {
        case "import":
            guard args.count > 1 else {
                print("Usage: swiss rss import <file.opml>")
                exit(1)
            }
            let path = args[1]
            guard FileManager.default.isReadableFile(atPath: path) else {
                print("Error: cannot read file: \(path)")
                exit(1)
            }
            let urls = RSSOPMLParser.parse(atPath: path)
            guard !urls.isEmpty else {
                print("No feed URLs found in OPML file.")
                exit(1)
            }
            print("Importing \(urls.count) feed(s)...")
            for url in urls {
                db.addFeed(url: url)
            }
            print("Done.")

        case "add":
            guard args.count > 1 else {
                print("Usage: swiss rss add <url>")
                exit(1)
            }
            let url = args[1]
            db.addFeed(url: url)
            print("Feed added: \(url)")

        default:
            // Treat as OPML file if readable
            if FileManager.default.isReadableFile(atPath: sub) {
                let urls = RSSOPMLParser.parse(atPath: sub)
                if !urls.isEmpty {
                    print("Importing \(urls.count) feed(s)...")
                    for url in urls {
                        db.addFeed(url: url)
                    }
                    print("Done.")
                }
            } else {
                print("Unknown subcommand: \(sub)")
                print("Usage: swiss rss [import <file>|add <url>]")
                exit(1)
            }
        }
    }

    let tui = RSSTUI(db: db)
    tui.run()
}
