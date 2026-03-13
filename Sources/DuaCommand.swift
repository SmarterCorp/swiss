import Foundation

func runDuaCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "dua-cli", binary: "dua")])

    let duaArgs = args.isEmpty ? ["interactive"] : args
    let argv = (["dua"] + duaArgs).map { strdup($0) } + [nil]
    execvp("dua", argv)

    // execvp only returns on failure
    perror("Failed to exec dua")
    exit(1)
}
