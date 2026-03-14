# Code Review Guidelines

## Project Context

swiss is a macOS CLI multitool (Swift, arm64, macOS 13+). It uses private Apple APIs,
IOKit, CoreWLAN, CGEventTap, and shell process execution. No test suite exists.
Security surface: file I/O, process spawning, system-wide event interception, PID management.

---

## Security (strict)

### Must reject

**Universal:**

- Hardcoded credentials, tokens, API keys, or secrets of any kind
- Unbounded reads from stdin, files, or process output — enforce reasonable size limits (also limit parsed entry counts)
- Untrusted external data flowing to destructive operations — paths parsed from external tools or data files must be validated against allowlists before deletion, process execution, or privilege escalation
- Percent-encoded or decoded paths — resolve symlinks and validate AFTER decoding, not before
- Path traversal: any file operation must resolve symlinks and validate the final path stays within expected boundaries
- Reading or writing files outside expected paths without explicit user intent

**macOS / CLI specific:**

- Shell command construction via string interpolation or concatenation — always use `Process` API with argument arrays
- Unsanitized user input passed to `Process`, `execvp`, `dlsym`, `NSWorkspace.open`, or URL construction
- New uses of `dlopen`/`dlsym` without documenting why the private API is necessary and what happens if it's removed in a future macOS version
- PID file operations without verifying the process belongs to swiss (prevent killing unrelated processes)
- New `CGEventTap` or accessibility-based features without documenting the required permissions and failure behavior
- Running `brew install` or any package manager command without user confirmation

### Must flag

**Universal:**

- TOCTOU windows — between validation and operation (especially in user-writable dirs); re-resolve if practical
- Changes to file permissions or ownership
- New network calls or URL scheme invocations
- Expansion of tilde (`~`) or environment variables in paths — verify no injection vector
- Deserialization of untrusted data (plists, JSON, XML) from untrusted paths — verify the path is validated against safe directories before reading

**macOS / CLI specific:**

- Any new `Process` or `execvp` call — verify arguments cannot be influenced by untrusted input
- Signal sending (`kill`, `SIGTERM`) — verify target PID is validated
- New uses of IOKit, CoreGraphics, or other system frameworks — check if public API alternatives exist
- Helper tool persistence — executables in `/Library/PrivilegedHelperTools/`, `*/Application Support/`, `/usr/local/libexec/` survive app uninstall; don't trust their existence as proof an app is installed
- osascript privilege escalation — verify admin operations also work under `sudo` (check `geteuid() == 0`)

---

## Correctness

### Must reject

**Universal:**

- Silently swallowing errors — failed operations must print a meaningful message to stderr and exit with non-zero code
- Redundant variable shadowing — re-declaring variables in inner scopes with identical values (copy-paste artifacts)
- Classification mismatches — items categorized based on metadata type instead of actual source path (e.g., system items classified as "user" because a type field says "agent" instead of checking the directory)

**macOS / CLI specific:**

- Force unwraps (`!`) on values that can legitimately be nil at runtime (e.g., file reads, process output, IOKit lookups, dictionary subscripts)
- Missing `guard`/`if let` for optional values from system APIs that may fail on different hardware configs
- Breaking changes to existing CLI interface (command names, argument order) without updating README.md and usage text

### Must flag

- Any new `exit()` call — verify the exit code is appropriate (0 for success, non-zero for errors)
- Changes to state files (`~/.swiss-display-state`, `~/.swiss-cursor.pid`) — verify read/write symmetry
- Changes to `build.sh` — verify all source files are included in compilation and frameworks are linked

---

## Code Quality

### Must flag

**Universal:**

- Functions longer than 50 lines — suggest extraction into parse/validate/execute helpers
- Duplicated logic across files (especially validation patterns, privilege escalation, error handling)
- Print to stdout for errors (should use stderr)
- Output readability — raw identifiers or cryptic system names shown to user instead of human-readable labels; group related items logically (by developer, vendor, category) rather than flat lists
- Fuzzy matching too broad — e.g., vendor prefix `com.microsoft` matching unrelated Microsoft apps; prefer exact match when explicit IDs are available, fall back to prefix only when no better signal exists

**macOS / CLI specific:**

- New string literals for file paths — prefer constants or a shared config
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
