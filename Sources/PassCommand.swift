import Foundation

func runPassCommand(args: [String]) {
    ensureOpInstalled()

    guard let action = args.first else {
        execOp(["item", "list"])
        return
    }

    switch action {
    case "get":
        guard args.count >= 2 else {
            fputs("Usage: swiss pass get <item-name>\n", stderr)
            exit(1)
        }
        execOp(["item", "get", args[1], "--fields", "password"])

    case "search":
        guard args.count >= 2 else {
            fputs("Usage: swiss pass search <query>\n", stderr)
            exit(1)
        }
        execOp(["item", "list", "--query"] + Array(args.dropFirst()))

    case "login":
        execOp(["signin"])

    case "help", "-h", "--help":
        printPassUsage()

    default:
        execOp(args)
    }
}

private func execOp(_ args: [String]) {
    let argv = (["op"] + args).map { strdup($0) } + [nil]
    execvp("op", argv)
    perror("Failed to exec op")
    exit(1)
}

private func printPassUsage() {
    print("Usage: swiss pass <command>")
    print("")
    print("Commands:")
    print("  (no args)           — list all items")
    print("  get <item>          — get password for an item")
    print("  search <query>      — search items")
    print("  login               — sign in to 1Password")
    print("  <op args>           — pass through to 1Password CLI")
}

private func ensureOpInstalled() {
    for candidate in ["/opt/homebrew/bin/op", "/usr/local/bin/op"] {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return
        }
    }

    var brewPath: String?
    for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            brewPath = candidate
            break
        }
    }

    guard let brew = brewPath else {
        fputs("Error: 1Password CLI is not installed and Homebrew was not found.\n", stderr)
        fputs("Install: brew install --cask 1password-cli\n", stderr)
        exit(1)
    }

    fputs("Installing 1Password CLI...\n", stderr)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: brew)
    process.arguments = ["install", "--cask", "1password-cli"]
    try? process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fputs("Error: Failed to install 1Password CLI.\n", stderr)
        exit(1)
    }
}
