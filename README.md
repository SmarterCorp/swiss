# swiss — CLI multitool for macOS

A lightweight command-line utility for managing displays, services, RSS feeds, AI translation, voice dictation, and more on macOS. Written in Swift, compiled with `swiftc`, no Xcode project required.

## Build

```bash
bash build.sh
bash build.sh install   # install to /usr/local/bin
```

Produces `build/swiss`. Target: `arm64-apple-macos13` (Apple Silicon).

## Quick Start

```bash
swiss dash                          # system dashboard
swiss status                        # check all services
swiss maintain                      # update everything
```

## Commands

| Command | Description |
|---|---|
| `swiss dash` | System dashboard — battery, network, services, feeds, ports |
| `swiss status` | Show status of all managed services |
| `swiss maintain` | Update all tools, models, and containers |
| `swiss display off/on` | Disconnect/reconnect external monitors |
| `swiss usb` | List USB devices |
| `swiss cursor start/stop` | Cursor teleporter between displays (Command+2) |
| `swiss textream [text\|file]` | Open Textream teleprompter |
| `swiss twitter [auth\|add\|remove\|list]` | Read Twitter via RSS (newsboat + self-hosted RSSHub) |
| `swiss rss [args]` | RSS reader (newsboat, auto-installs) |
| `swiss rss -ru` | RSS reader with articles pre-translated to Russian |
| `swiss translate [text\|file]` | Translate English to Russian via Ollama (gemma3) |
| `swiss voice` | Launch Pipit voice dictation (auto-installs) |
| `swiss prompt add/remove/list` | Manage text expansions via Espanso |
| `swiss dua [args]` | Disk usage analyzer (auto-installs) |
| `swiss top [args]` | Activity monitor (auto-installs) |
| `swiss wifi` | Show WiFi network info |
| `swiss battery` | Show battery status and health |
| `swiss ports` | List open listening ports |
| `swiss trash [files...]` | Move files to Trash (no args: show info) |
| `swiss clipboard [copy\|paste]` | Copy stdin / paste to stdout |

### Dashboard

```
$ swiss dash
╭─ System ─────────────────────────────────────────────╮
│ Battery   94% [#########.] on battery                │
│ Network   WiFi: -50 dBm (Excellent)                  │
│ Displays  1 external                                 │
│ Disk      78 GB free / 460 GB                        │
╰──────────────────────────────────────────────────────╯
╭─ Services ───────────────────────────────────────────╮
│ [+] espanso     [+] ollama      [+] docker           │
│ [-] cursor      [+] rsshub      [-] pipit            │
╰──────────────────────────────────────────────────────╯
╭─ Feeds ──────────────────────────────────────────────╮
│ RSS       10 feeds                                   │
│ Twitter   1 accounts (@karpathy)                     │
│ Prompts   1 expansions                               │
╰──────────────────────────────────────────────────────╯
╭─ Network ────────────────────────────────────────────╮
│ IP        192.168.68.50                              │
│ Ports     6 listening (1200, 5000, 7000, 11434)      │
╰──────────────────────────────────────────────────────╯
```

### Twitter via RSS

Self-hosted RSSHub via Docker. Auto-installs Docker Desktop if needed.

```bash
swiss twitter auth <token>      # set Twitter auth token (from x.com cookies)
swiss twitter add @karpathy     # subscribe to a Twitter account
swiss twitter                   # open newsboat with Twitter feeds
swiss twitter -ru               # open with articles translated to Russian
```

### AI Translation

Uses Ollama with gemma3 model. Auto-installs Ollama and pulls the model on first use.

```bash
swiss translate "Hello world"           # translate text
swiss translate file.txt                # translate a file
cat article.txt | swiss translate       # translate from stdin
swiss rss -ru                           # pre-translate all RSS feeds
```

### Voice Dictation

Installs and launches Pipit — local speech-to-text. Press Option key, speak, release to paste text.

```bash
swiss voice         # install (if needed) and launch Pipit
```

### Text Expansions

Manages text snippets via Espanso. Type a trigger anywhere and it expands.

```bash
swiss prompt add :addr 123 Main Street, Dubai
swiss prompt add :sig Best regards, John
swiss prompt list
swiss prompt remove :addr
swiss prompt start                      # start Espanso daemon
swiss prompt stop
```

### Display Management

```bash
swiss display off       # disconnect external monitors
swiss display on        # reconnect them
```

Uses the private API `CGSConfigureDisplayEnabled`. Display IDs saved to `~/.swiss-display-state`.

### Cursor Teleporter

```bash
swiss cursor start &    # start daemon (Command+2 to jump between displays)
swiss cursor stop       # stop daemon
```

Requires Accessibility permission.

## Services & Dependencies

| Service | Installed via | Used by |
|---|---|---|
| newsboat | `brew install newsboat` | `rss`, `twitter` |
| Ollama + gemma3 | `brew install ollama` | `translate`, `rss -ru` |
| Docker Desktop | `brew install --cask docker` | `twitter` (RSSHub container) |
| Espanso | `brew install --cask espanso` | `prompt` |
| Pipit | GitHub releases DMG | `voice` |
| dua-cli | `brew install dua-cli` | `dua` |
| bottom | `brew install bottom` | `top` |

All dependencies are auto-installed on first use. Run `swiss maintain` to update everything.

## File Structure

```
Sources/
  main.swift              — CLI entry point and command dispatcher
  DashCommand.swift       — system dashboard
  StatusCommand.swift     — service status checks
  MaintainCommand.swift   — update all tools and services
  DisplayCommand.swift    — display on/off (private CoreGraphics API)
  USBCommand.swift        — USB device listing (system_profiler + IOKit)
  CursorCommand.swift     — cursor teleporter daemon (CGEventTap)
  TextreamCommand.swift   — Textream app launcher
  TwitterCommand.swift    — Twitter via RSS (RSSHub + newsboat)
  RSSCommand.swift        — newsboat wrapper
  TranslateCommand.swift  — EN→RU translation via Ollama
  FeedTranslator.swift    — batch feed translation with caching
  NewsboatConfig.swift    — newsboat config generation
  VoiceCommand.swift      — Pipit voice dictation installer
  PromptCommand.swift     — Espanso text expansion manager
  DockerDependency.swift  — Docker auto-install and container management
  BrewDependency.swift    — Homebrew auto-install
  DuaCommand.swift        — dua-cli wrapper
  TopCommand.swift        — bottom (btm) wrapper
  WiFiCommand.swift       — WiFi info
  BatteryCommand.swift    — battery status
  PortsCommand.swift      — listening ports
  TrashCommand.swift      — trash management
  ClipboardCommand.swift  — clipboard copy/paste
build.sh                  — single-file build script
```

## State & Config Files

| File | Purpose |
|---|---|
| `~/.swiss-display-state` | Disconnected display IDs |
| `~/.swiss-cursor.pid` | Cursor teleporter daemon PID |
| `~/.config/swiss/twitter` | Twitter auth token |
| `~/.config/swiss/newsboat-config` | Generated newsboat config |
| `~/.cache/swiss/translated/` | Translation cache (7-day eviction) |
| `~/Library/Application Support/espanso/match/swiss.yml` | Text expansion triggers |
