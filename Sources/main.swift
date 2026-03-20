import Foundation

let version = "1.7.0"
let jsonMode = CommandLine.arguments.contains("--json")
let args = Array(CommandLine.arguments.dropFirst().filter { $0 != "--json" })

func printUsage() {
    print("swiss \(version) — CLI multitool")
    print("")
    print("Status & Info:")
    print("  battery                — show battery status and health")
    print("  wifi                   — show WiFi network info")
    print("  ports                  — list open listening ports")
    print("  usb                    — list USB devices")
    print("  status                 — show all services status")
    print("  dash                   — system dashboard")
    print("")
    print("Utilities:")
    print("  clipboard [copy|paste] — copy stdin / paste to stdout")
    print("  prompt [add|remove|list] — manage text expansions (Espanso)")
    print("  pass [get|search|login]  — 1Password CLI")
    print("  translate [text|file]    — translate English to Russian (Ollama)")
    print("")
    print("Switchers:")
    print("  display off|on             — disconnect/reconnect external monitors")
    print("  cursor start|stop          — cursor teleporter (Command+2 to jump between displays)")
    print("  sleep off|on|caffeine      — prevent/allow system sleep")
    print("  menubar [list|show|hide]   — manage menu bar icons")
    print("")
    print("Maintenance:")
    print("  install [list|<app>]        — bootstrap apps for a new Mac")
    print("  clean [--dry-run|uninstall|login] — system cleanup")
    print("  maintain                    — update all tools and services")
    print("")
    print("Apps:")
    print("  textream [text|file]              — Textream teleprompter")
    print("  twitter [auth|add|remove|list]    — Twitter via RSS (newsboat + RSSHub)")
    print("  rss [args]                        — RSS reader (newsboat, auto-installs)")
    print("  dua [args]                        — disk usage analyzer (auto-installs)")
    print("  top [args]                        — activity monitor (auto-installs)")
    print("")
    print("  version              — print version")
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
case "prompt":
    runPromptCommand(args: Array(args.dropFirst()))
case "pass":
    runPassCommand(args: Array(args.dropFirst()))
case "menubar":
    runMenuBarCommand(args: Array(args.dropFirst()))
case "install":
    runInstallCommand(args: Array(args.dropFirst()))
case "clean":
    runCleanCommand(args: Array(args.dropFirst()))
case "sleep":
    runSleepCommand(args: Array(args.dropFirst()))
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
