import Foundation

func runDuaCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "dua-cli", binary: "dua")])

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let duaArgs = args.isEmpty ? ["interactive", home] : args
    let argv = (["dua"] + duaArgs).map { strdup($0) } + [nil]
    execvp("dua", argv)

    // execvp only returns on failure
    perror("Failed to exec dua")
    exit(1)
}
