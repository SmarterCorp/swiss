import Foundation
import AppKit

func runTextreamCommand(args: [String]) {
    let text: String?

    if let arg = args.first {
        // Check if it's a readable file
        if FileManager.default.isReadableFile(atPath: arg) {
            do {
                text = try String(contentsOfFile: arg, encoding: .utf8)
            } catch {
                print("Error reading file: \(error.localizedDescription)")
                exit(1)
            }
        } else {
            text = arg
        }
    } else if isatty(STDIN_FILENO) == 0 {
        // Read from stdin (pipe)
        text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
    } else {
        text = nil
    }

    let url: URL
    if let text = text, !text.isEmpty {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Error: failed to encode text")
            exit(1)
        }
        guard let u = URL(string: "textream://read?text=\(encoded)") else {
            print("Error: failed to build URL")
            exit(1)
        }
        url = u
    } else {
        url = URL(string: "textream://")!
    }

    NSWorkspace.shared.open(url)
}
