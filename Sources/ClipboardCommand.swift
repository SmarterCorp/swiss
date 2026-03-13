import Foundation
import AppKit

func runClipboardCommand(args: [String]) {
    let subcommand = args.first ?? "paste"

    switch subcommand {
    case "copy":
        let input: String
        if isatty(STDIN_FILENO) == 0 {
            input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } else {
            print("Usage: echo 'text' | swiss clipboard copy")
            exit(1)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(input, forType: .string)
        let charCount = input.count
        print("Copied \(charCount) characters to clipboard.")

    case "paste":
        let pb = NSPasteboard.general
        if let text = pb.string(forType: .string) {
            print(text, terminator: "")
        }

    default:
        print("Usage: swiss clipboard [copy|paste]")
        print("  copy  — read stdin and copy to clipboard")
        print("  paste — print clipboard contents to stdout")
        exit(1)
    }
}
