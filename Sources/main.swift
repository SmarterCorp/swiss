import Foundation

let version = "1.3.0"
let args = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("swiss \(version) — CLI multitool")
    print("")
    print("Commands:")
    print("  display off   — disconnect external monitors")
    print("  display on    — reconnect external monitors")
    print("  usb           — list USB devices")
    print("  cursor start  — start cursor teleporter (Command+2 to jump between displays)")
    print("  cursor stop   — stop cursor teleporter")
    print("  textream [text|file] — open Textream teleprompter with optional text or file")
    print("  twitter [auth|add|remove|list] — read Twitter via RSS (newsboat + RSSHub)")
    print("  translate [text|file]         — translate English to Russian (Ollama)")
    print("  voice                        — launch Pipit voice dictation (auto-installs)")
    print("  prompt [add|remove|list]     — manage text expansions (Espanso)")
    print("  pass [get|search|login]     — 1Password CLI")
    print("  rss [args]          — RSS reader (newsboat, auto-installs via brew)")
    print("  dua [args]          — disk usage analyzer (auto-installs via brew)")
    print("  top [args]          — activity monitor (auto-installs via brew)")
    print("  wifi                — show WiFi network info")
    print("  battery             — show battery status and health")
    print("  ports               — list open listening ports")
    print("  trash [files...]    — move files to Trash (no args: show info)")
    print("  clipboard [copy|paste] — copy stdin / paste to stdout")
    print("  status              — show all services status")
    print("  maintain            — update all tools and services")
    print("  dash                — system dashboard")
    print("  version             — print version")
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
case "twitter":
    runTwitterCommand(args: Array(args.dropFirst()))
case "translate":
    runTranslateCommand(args: Array(args.dropFirst()))
case "voice":
    runVoiceCommand()
case "prompt":
    runPromptCommand(args: Array(args.dropFirst()))
case "pass":
    runPassCommand(args: Array(args.dropFirst()))
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
case "status":
    runStatusCommand()
case "maintain":
    runMaintainCommand()
case "dash":
    runDashCommand()
case "version", "-v", "--version":
    print("swiss \(version)")
case "help", "-h", "--help":
    printUsage()
default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}
