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
    print("  rss [args]          — RSS reader (newsboat, auto-installs via brew)")
    print("  dua [args]          — disk usage analyzer (auto-installs via brew)")
    print("  top [args]          — activity monitor (auto-installs via brew)")
    print("  wifi                — show WiFi network info")
    print("  battery             — show battery status and health")
    print("  ports               — list open listening ports")
    print("  trash [files...]    — move files to Trash (no args: show info)")
    print("  clipboard [copy|paste] — copy stdin / paste to stdout")
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
case "wifi":
    runWiFiCommand()
case "battery":
    runBatteryCommand()
case "ports":
    runPortsCommand()
case "trash":
    runTrashCommand(args: Array(args.dropFirst()))
case "clipboard":
    runClipboardCommand(args: Array(args.dropFirst()))
case "help", "-h", "--help":
    printUsage()
default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}
