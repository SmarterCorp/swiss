import Foundation
import AppKit

private func trashInfo() {
    let fm = FileManager.default
    let trashURL = fm.urls(for: .trashDirectory, in: .userDomainMask).first!

    do {
        let items = try fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        var totalSize: Int64 = 0
        for item in items {
            let values = try item.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            totalSize += Int64(values.totalFileAllocatedSize ?? 0)
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        print("Trash: \(items.count) items (\(formatter.string(fromByteCount: totalSize)))")
    } catch {
        print("Failed to read Trash: \(error.localizedDescription)")
    }
}

func runTrashCommand(args: [String]) {
    if args.isEmpty {
        trashInfo()
        return
    }

    let fm = FileManager.default
    var moved = 0
    var failed = 0

    for path in args {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL

        guard fm.fileExists(atPath: url.path) else {
            print("Not found: \(path)")
            failed += 1
            continue
        }

        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            print("Trashed: \(path)")
            moved += 1
        } catch {
            print("Failed to trash \(path): \(error.localizedDescription)")
            failed += 1
        }
    }

    if args.count > 1 {
        print("\n\(moved) trashed, \(failed) failed")
    }
}
