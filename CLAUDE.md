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

**Universal principles:**

- **English only** — all messages, comments, strings, variable names in English
- **Errors to stderr**, data to stdout — never mix channels
- **Functions under 50 lines** — extract if longer; split into parse/validate/execute helpers
- **No silent failures** — always print meaningful error message and exit non-zero
- **User-friendly output** — group related items logically (by developer, vendor, category), show human-readable names instead of raw identifiers, explain what items are and where they came from
- **Minimize user friction** — batch operations requiring credentials; offer both interactive and non-interactive modes

**macOS / Swift specific:**

- **No force unwraps** on values from system APIs (file reads, process output, IOKit, dict lookups)
- **Process API with argument arrays** — never construct shell commands via string interpolation
- **Auto-install dependencies** — tools installed via Homebrew on first use (with user confirmation)
- **State files** go in `~/.swiss-*` or `~/.config/swiss/`
- **Path safety** — resolve symlinks, validate paths stay within expected boundaries, expand tilde safely
- **Minimize password prompts** — support `sudo` for zero-prompt mode; fall back to `osascript ... with administrator privileges` when not root

## Security Rules (strict)

**Universal principles:**

- No hardcoded credentials/tokens/secrets
- Enforce size limits on unbounded reads (stdin, files, process output, parsed entries)
- Untrusted external data — validate/resolve all parsed paths before any filesystem operation or process argument
- Path validation AFTER decoding — percent-encoding, URL decoding, tilde expansion must happen before symlink resolution and boundary checks

**macOS / CLI specific:**

- No shell injection: always use `Process` with argument arrays, never string interpolation for commands
- Sanitize user input before passing to `Process`, `NSWorkspace.open`, or URL construction
- Validate PID belongs to swiss before sending signals
- Verify code signatures after installing external apps
- Use `--env-file` for Docker secrets (not `-e`, which leaks to `ps aux`)
- **Helper tool directories** (`/Library/PrivilegedHelperTools/`, `/Library/Application Support/`, `~/Library/Application Support/`, `/usr/local/libexec/`) — executables here persist after app uninstall; don't trust their existence as proof the parent app is installed
- **Privilege escalation** — support `sudo` (check `geteuid() == 0`) for direct execution; fall back to `osascript ... with administrator privileges` when not root

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
- **After push/release** — always verify CI/CD passes (`gh run list`, `gh run watch`). Do not report a release as successful until all workflows (build + release) complete with green status. If CI fails, investigate and fix before proceeding.

### Release Checklist

When asked to make a release:

1. Update `README.md` to reflect any new/changed commands, flags, or behavior
2. Bump version in `Sources/main.swift`
3. Commit all changes (README, version bump, code)
4. If on a feature branch — push, create/update PR, squash-merge into `main`
5. Tag the release on `main` (`git tag v<version>`) and push the tag
6. Verify both `build.yml` and `release.yml` workflows pass

## What NOT to Do

- Don't use Swift Package Manager or Xcode — this is a single `swiftc` build
- Don't add dependencies that require SPM
- Don't break existing CLI interface (command names, argument order) without updating README and help text
- Don't print errors to stdout — use stderr
- Don't silently swallow errors — always print meaningful message and exit non-zero
- Don't use APIs requiring macOS > 13 without `@available` checks
- Don't run `brew install` without user confirmation
