import Foundation

struct BrewDependency {
    let package: String  // brew formula name, e.g. "dua-cli"
    let binary: String   // binary to check, e.g. "dua"
}

func findBrewPath() -> String? {
    for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

func ensureBrewDependencies(_ deps: [BrewDependency]) {
    for dep in deps {
        // Check if binary exists
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        whichProcess.arguments = ["which", dep.binary]
        whichProcess.standardOutput = FileHandle.nullDevice
        whichProcess.standardError = FileHandle.nullDevice
        try? whichProcess.run()
        whichProcess.waitUntilExit()

        if whichProcess.terminationStatus == 0 {
            continue
        }

        // Binary missing — find brew
        guard let brew = findBrewPath() else {
            fputs("Error: '\(dep.binary)' is not installed and Homebrew was not found.\n", stderr)
            fputs("Install Homebrew: https://brew.sh\n", stderr)
            fputs("Then run: brew install \(dep.package)\n", stderr)
            exit(1)
        }

        fputs("Installing \(dep.package) via Homebrew...\n", stderr)

        let installProcess = Process()
        installProcess.executableURL = URL(fileURLWithPath: brew)
        installProcess.arguments = ["install", dep.package]
        try? installProcess.run()
        installProcess.waitUntilExit()

        if installProcess.terminationStatus != 0 {
            fputs("Error: Failed to install \(dep.package) via Homebrew.\n", stderr)
            exit(1)
        }
    }
}
