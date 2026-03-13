import Foundation

func runTopCommand(args: [String]) {
    ensureBrewDependencies([BrewDependency(package: "bottom", binary: "btm")])
    let argv = (["btm"] + args).map { strdup($0) } + [nil]
    execvp("btm", argv)
    perror("Failed to exec btm")
    exit(1)
}
