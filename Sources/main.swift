import Foundation

let args = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("swiss — CLI multitool")
    print("")
    print("Commands:")
    print("  display off   — disconnect external monitors")
    print("  display on    — reconnect external monitors")
    print("  usb           — list USB devices")
    print("  cursor start  — start cursor teleporter (Command+2 to jump between displays)")
    print("  cursor stop   — stop cursor teleporter")
    print("  textream [text|file] — open Textream teleprompter with optional text or file")
    print("  rss                 — launch RSS reader TUI")
    print("  rss import <file>   — import feeds from OPML, then launch TUI")
    print("  rss add <url>       — add single feed, then launch TUI")
    print("  dua [args]          — disk usage analyzer (auto-installs via brew)")
    print("  top [args]          — activity monitor (auto-installs via brew)")
    print("")
    print("Usage: swiss <command> [args]")
}

guard let command = args.first else {
    printUsage()
    exit(1)
}

switch command {
case "display":
    runDisplayCommand(args: Array(args.dropFirst()))
case "usb":
    runUSBCommand()
case "cursor":
    runCursorCommand(args: Array(args.dropFirst()))
case "textream":
    runTextreamCommand(args: Array(args.dropFirst()))
case "rss":
    runRSSCommand(args: Array(args.dropFirst()))
case "dua":
    runDuaCommand(args: Array(args.dropFirst()))
case "top":
    runTopCommand(args: Array(args.dropFirst()))
case "help", "-h", "--help":
    printUsage()
default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}
