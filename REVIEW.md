# Code Review Guidelines

## Project Context

swiss is a macOS CLI multitool (Swift, arm64, macOS 13+). It uses private Apple APIs,
IOKit, CoreWLAN, CGEventTap, and shell process execution. No test suite exists.
Security surface: file I/O, process spawning, system-wide event interception, PID management.

---

## Security (strict)

### Must reject

- Shell command construction via string interpolation or concatenation — always use `Process` API with argument arrays
- Unsanitized user input passed to `Process`, `execvp`, `dlsym`, `NSWorkspace.open`, or URL construction
- Reading or writing files outside expected paths (`~/.swiss-*`, `~/.newsboat/`) without explicit user intent
- Hardcoded credentials, tokens, API keys, or secrets of any kind
- New uses of `dlopen`/`dlsym` without documenting why the private API is necessary and what happens if it's removed in a future macOS version
- PID file operations without verifying the process belongs to swiss (prevent killing unrelated processes)
- Unbounded reads from stdin, files, or process output — enforce reasonable size limits
- Path traversal: any file operation must resolve symlinks and validate the final path stays within expected boundaries
- New `CGEventTap` or accessibility-based features without documenting the required permissions and failure behavior
- Running `brew install` or any package manager command without user confirmation

### Must flag

- Any new `Process` or `execvp` call — verify arguments cannot be influenced by untrusted input
- Changes to file permissions or ownership
- New network calls or URL scheme invocations
- Expansion of tilde (`~`) or environment variables in paths — verify no injection vector
- Signal sending (`kill`, `SIGTERM`) — verify target PID is validated
- New uses of IOKit, CoreGraphics, or other system frameworks — check if public API alternatives exist

---

## Correctness

### Must reject

- Force unwraps (`!`) on values that can legitimately be nil at runtime (e.g., file reads, process output, IOKit lookups)
- Missing `guard`/`if let` for optional values from system APIs that may fail on different hardware configs
- Silently swallowing errors — failed operations must print a meaningful message to stderr and exit with non-zero code
- Breaking changes to existing CLI interface (command names, argument order) without updating README.md and usage text in main.swift

### Must flag

- Any new `exit()` call — verify the exit code is appropriate (0 for success, non-zero for errors)
- Changes to state files (`~/.swiss-display-state`, `~/.swiss-cursor.pid`) — verify read/write symmetry
- Changes to `build.sh` — verify all source files are included in compilation and frameworks are linked

---

## Code Quality

### Must flag

- Functions longer than 50 lines — suggest extraction
- Duplicated logic across command files (especially process spawning patterns)
- New string literals for file paths — prefer constants or a shared config
- Print to stdout for errors (should use stderr via `FileHandle.standardError`)
- Missing `set -e` or error handling in shell scripts

### Skip

- Formatting-only changes (whitespace, line breaks) with no logic changes
- Comment-only changes
- Changes to `.gitignore`, `package-lock.json`, or `.claude/` directory
- README.md cosmetic edits

---

## Compatibility

### Must flag

- Any API usage that requires macOS version higher than 13 — must be documented and availability-checked
- Changes to `build.sh` target architecture — currently arm64 only, flag if broadened or narrowed
- New Homebrew dependencies — verify the formula name is correct and the tool is actively maintained
- Deprecation warnings from Apple frameworks — prefer migrating to supported APIs
