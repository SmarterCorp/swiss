# CLAUDE.md — Development Guide for swiss

## Project Overview

**swiss** is a macOS CLI multitool written in pure Swift (no SPM, no Xcode project).
Binary name: `swiss`. Target: `arm64-apple-macos13`.
Current version is in `Sources/main.swift` (`let version = "x.y.z"`).

## Build

```bash
bash build.sh        # compiles to build/swiss
bash build.sh install  # copies to /usr/local/bin
```

Build uses raw `swiftc` with explicit source file list and framework links.
**When adding a new source file, you MUST add it to `build.sh`.**

## Architecture

- **One file per command** in `Sources/` (e.g., `BatteryCommand.swift`, `CleanCommand.swift`)
- `Sources/main.swift` — entry point, version, `--json` flag, command dispatcher (`switch`)
- Each command exposes a top-level `func run<Name>Command(args:)` called from `main.swift`
- Shared helpers: `BrewDependency.swift` (auto-install via brew), `DockerDependency.swift`, `JSONOutput.swift`
- `SwissApp/` — separate SwiftUI menu bar app that calls the CLI via `CLIBridge`

## Adding a New Command

1. Create `Sources/<Name>Command.swift` with `func run<Name>Command(args: [String])`
2. Add the source file to `build.sh`
3. Add a `case` in the `switch` block in `main.swift`
4. Add help line in `printUsage()` in `main.swift`
5. Support `--json` flag if the command outputs data (use `printJSON()` from `JSONOutput.swift`)
6. Update `README.md`

## Code Conventions

- **English only** — all messages, comments, strings, variable names in English
- **Errors to stderr**: `FileHandle.standardError.write(...)`, then `exit(1)`
- **No force unwraps** on values from system APIs (file reads, process output, IOKit)
- **Process API with argument arrays** — never construct shell commands via string interpolation
- **Auto-install dependencies** — tools installed via Homebrew on first use (with user confirmation)
- **State files** go in `~/.swiss-*` or `~/.config/swiss/`
- **Functions under 50 lines** — extract if longer
- **Path safety** — resolve symlinks, validate paths stay within expected boundaries, expand tilde safely

## Security Rules (strict)

- No shell injection: always use `Process` with argument arrays, never string interpolation for commands
- No hardcoded credentials/tokens/secrets
- Sanitize user input before passing to `Process`, `NSWorkspace.open`, or URL construction
- Validate PID belongs to swiss before sending signals
- Enforce size limits on unbounded reads (stdin, files, process output)
- Verify code signatures after installing external apps
- Use `--env-file` for Docker secrets (not `-e`, which leaks to `ps aux`)

## Git & PR Workflow

- Branch naming: `feature/<name>` for new features, fix branches for bugs
- PRs go to `main` branch
- Commit messages: imperative mood, explain what and why
- Squash-merge PRs via GitHub
- Co-Authored-By trailer when AI-assisted
- CI runs on every push to main and all PRs (`.github/workflows/build.yml`)
- Releases triggered by version tags (`v*`) via `.github/workflows/release.yml`

### Review Gates

- **Before push/PR** — run a **code review** (check code quality, correctness, conventions from `REVIEW.md`)
- **Before release** — run a **security review** (audit all security rules, process spawning, path handling, secrets, input validation)

## What NOT to Do

- Don't use Swift Package Manager or Xcode — this is a single `swiftc` build
- Don't add dependencies that require SPM
- Don't break existing CLI interface (command names, argument order) without updating README and help text
- Don't print errors to stdout — use stderr
- Don't silently swallow errors — always print meaningful message and exit non-zero
- Don't use APIs requiring macOS > 13 without `@available` checks
- Don't run `brew install` without user confirmation
