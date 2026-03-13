import Foundation

func runRSSCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "newsboat", binary: "newsboat")])

    let dir = NSHomeDirectory() + "/.newsboat"
    let urlsFile = dir + "/urls"
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir) {
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: urlsFile) {
        fm.createFile(atPath: urlsFile, contents: nil)
    }

    let argv = (["newsboat"] + args).map { strdup($0) } + [nil]
    execvp("newsboat", argv)

    perror("Failed to exec newsboat")
    exit(1)
}
