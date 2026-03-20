import Foundation
import IOKit.ps
import CoreWLAN

// MARK: - Data & State

private struct TUILine {
    let text: String
    let isCommand: Bool
}

private enum TUIMode {
    case welcome
    case repl
}

private var tuiMode: TUIMode = .welcome
private var shouldQuit = false
private var scrollBuffer: [TUILine] = []
private var scrollOffset: Int = 0
private var inputBuffer: String = ""
private var cursorPos: Int = 0
private var commandHistory: [String] = []
private var historyIndex: Int = -1
private var historyFile: String = ""

private var headerWin: OpaquePointer?
private var scrollWin: OpaquePointer?
private var inputWin: OpaquePointer?
private var statusWin: OpaquePointer?

private let tuiCommands = [
    "battery", "wifi", "ports", "usb", "status", "dash",
    "clipboard", "prompt", "pass", "translate",
    "display", "cursor", "sleep", "menubar",
    "install", "clean", "maintain",
    "textream", "twitter", "rss", "dua", "top",
    "version", "help", "clear", "home", "menu", "back", "welcome", "quit", "exit",
]

private let terminalTakeoverCommands = ["rss", "dua", "top"]
private let maxScrollBuffer = 10000
private let minRows: Int32 = 5
private let minCols: Int32 = 40

// Quick action mappings
private let quickActions: [(key: String, cmd: String, desc: String)] = [
    ("1", "dash",    "System dashboard"),
    ("2", "status",  "Services status"),
    ("3", "battery", "Battery & health"),
    ("4", "wifi",    "Network info"),
    ("5", "ports",   "Listening ports"),
    ("6", "clean",   "System cleanup"),
]
private let quickApps: [(key: String, cmd: String, desc: String)] = [
    ("r", "rss",     "RSS reader"),
    ("t", "top",     "Activity monitor"),
    ("d", "dua",     "Disk usage"),
]

// Cached system info
private var cachedBattery: (pct: Int, charging: Bool) = (0, false)
private var cachedWifi: String = "disconnected"
private var cachedDiskFree: Int = 0

// Path to own binary
private var swissBinary: String = ""

// MARK: - Entry Point

func runTUICommand(args: [String]) {
    setlocale(LC_ALL, "")
    swissBinary = tuiResolveBinaryPath()
    historyFile = NSHomeDirectory() + "/.swiss-tui-history"
    loadHistory()
    tuiRefreshSystemInfo()
    tuiInitCurses()

    if LINES < minRows || COLS < minCols {
        endwin()
        fputs("Terminal too small (need \(minRows)x\(minCols), got \(LINES)x\(COLS))\n", stderr)
        return
    }

    setupWindows()
    drawAll()

    while !shouldQuit {
        let ch = wgetch(inputWin)
        tuiHandleKeypress(ch)
    }

    tuiCleanup()
}

private func tuiInitCurses() {
    initscr()
    start_color()
    use_default_colors()
    cbreak()
    noecho()
    keypad(stdscr, true)

    init_pair(1, Int16(COLOR_BLACK), Int16(COLOR_CYAN))    // header bar
    init_pair(2, Int16(COLOR_CYAN), -1)                     // command prompt
    init_pair(3, Int16(COLOR_WHITE), -1)                    // output text
    init_pair(4, Int16(COLOR_BLACK), Int16(COLOR_WHITE))    // status bar
    init_pair(5, Int16(COLOR_CYAN), -1)                     // logo
    init_pair(6, Int16(COLOR_YELLOW), -1)                   // menu keys [1]
    init_pair(7, Int16(COLOR_WHITE), -1)                    // dim hint
    init_pair(8, Int16(COLOR_GREEN), -1)                    // progress bar
}

// MARK: - System Info

private func tuiRefreshSystemInfo() {
    cachedBattery = tuiGetBatteryInfo()
    cachedWifi = tuiGetWifiSSID() ?? "disconnected"
    cachedDiskFree = tuiGetDiskFreeGB()
}

private func tuiGetBatteryInfo() -> (pct: Int, charging: Bool) {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
    guard let source = sources.first else { return (0, false) }
    let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] ?? [:]
    let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
    let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
    let pct = maxCap > 0 ? capacity * 100 / maxCap : 0
    let charging = (desc[kIOPSIsChargingKey] as? Bool) == true
    return (pct, charging)
}

private func tuiGetWifiSSID() -> String? {
    return CWWiFiClient.shared().interface()?.ssid()
}

private func tuiResolveBinaryPath() -> String {
    let arg0 = CommandLine.arguments.first ?? "swiss"
    if arg0.contains("/") { return arg0 }
    // Resolve from PATH using `which`
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [arg0]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
        return path
    }
    return "/usr/local/bin/swiss"
}

private func tuiGetDiskFreeGB() -> Int {
    guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
          let free = attrs[.systemFreeSize] as? Int64 else { return 0 }
    return Int(free / (1024 * 1024 * 1024))
}

// MARK: - Windows

private func setupWindows() {
    let rows = Int(LINES)
    let cols = Int(COLS)

    if let w = headerWin { delwin(w) }
    if let w = scrollWin { delwin(w) }
    if let w = inputWin { delwin(w) }
    if let w = statusWin { delwin(w) }

    let scrollHeight = max(1, Int32(rows - 3))
    headerWin = newwin(1, Int32(cols), 0, 0)
    scrollWin = newwin(scrollHeight, Int32(cols), 1, 0)
    inputWin = newwin(1, Int32(cols), Int32(rows - 2), 0)
    statusWin = newwin(1, Int32(cols), Int32(rows - 1), 0)

    keypad(inputWin, true)
    scrollok(scrollWin, true)
}

private func drawAll() {
    drawHeader()
    if tuiMode == .welcome {
        drawWelcome()
    } else {
        drawScrollArea()
    }
    drawInput()
    drawStatusBar()
}

// MARK: - Header

private func drawHeader() {
    guard let win = headerWin else { return }
    werase(win)
    wbkgd(win, UInt32(COLOR_PAIR(1)))
    mvwaddstr(win, 0, 0, " swiss \(version)")
    wrefresh(win)
}

// MARK: - Welcome Screen

private let asciiLogo: [String] = [
    "  ____  _    _ ___ ____ ____",
    " / ___|| |  | |_ _/ ___/ ___|",
    " \\___ \\| |/\\| || |\\___ \\___ \\",
    "  ___) |  /\\  || | ___) ___) |",
    " |____/ \\/  \\/|___|____/____/",
]

private func drawWelcome() {
    guard let win = scrollWin else { return }
    werase(win)

    let rows = Int(getmaxy(win))
    let cols = Int(getmaxx(win))

    let logoHeight = asciiLogo.count
    let summaryHeight = 4
    let menuHeight = quickActions.count + quickApps.count + 5
    let tipHeight = 2
    let totalContent = logoHeight + 1 + summaryHeight + menuHeight + tipHeight
    var row = max(1, (rows - totalContent) / 2)

    drawLogo(win: win, startRow: &row, cols: cols)
    row += 1
    drawSystemSummary(win: win, startRow: &row, cols: cols)
    row += 1
    if cols >= 50 {
        drawQuickActions(win: win, startRow: &row, cols: cols)
        row += 1
    }
    drawTip(win: win, row: row, cols: cols)

    wrefresh(win)
}

private func drawLogo(win: OpaquePointer, startRow: inout Int, cols: Int) {
    let logoWidth = asciiLogo.first?.count ?? 0
    let startCol = max(0, (cols - logoWidth - 10) / 2)

    wattron(win, COLOR_PAIR(5) | Int32(CURSES_A_BOLD))
    for (i, line) in asciiLogo.enumerated() {
        mvwaddstr(win, Int32(startRow + i), Int32(startCol), line)
    }
    wattroff(win, COLOR_PAIR(5) | Int32(CURSES_A_BOLD))

    let versionStr = "v\(version)"
    wattron(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))
    mvwaddstr(win, Int32(startRow + asciiLogo.count - 1), Int32(startCol + logoWidth + 2), versionStr)
    wattroff(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))

    startRow += asciiLogo.count
}

private func drawSystemSummary(win: OpaquePointer, startRow: inout Int, cols: Int) {
    let indent = max(0, (cols - 50) / 2)

    let (pct, charging) = cachedBattery
    let filled = pct / 10
    let bar = "[" + String(repeating: "#", count: filled) + String(repeating: ".", count: 10 - filled) + "]"
    let batStatus = charging ? "charging" : "on battery"

    mvwaddstr(win, Int32(startRow), Int32(indent), "Battery: ")
    wattron(win, COLOR_PAIR(8) | Int32(CURSES_A_BOLD))
    waddstr(win, "\(pct)% ")
    wattroff(win, COLOR_PAIR(8) | Int32(CURSES_A_BOLD))
    wattron(win, COLOR_PAIR(8))
    waddstr(win, bar)
    wattroff(win, COLOR_PAIR(8))
    wattron(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))
    waddstr(win, " \(batStatus)")
    wattroff(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))
    startRow += 1

    mvwaddstr(win, Int32(startRow), Int32(indent), "WiFi:    ")
    waddstr(win, cachedWifi)
    startRow += 1

    mvwaddstr(win, Int32(startRow), Int32(indent), "Disk:    ")
    waddstr(win, "\(cachedDiskFree) GB free")
    startRow += 1
}

private func drawQuickActions(win: OpaquePointer, startRow: inout Int, cols: Int) {
    let menuWidth = 48
    let indent = max(0, (cols - menuWidth) / 2)
    let inner = menuWidth - 4

    let titlePad = String(repeating: "-", count: max(0, inner - 16))
    mvwaddstr(win, Int32(startRow), Int32(indent), "+-" + " Quick Actions " + titlePad + "-+")
    startRow += 1

    let emptyLine = String(repeating: " ", count: inner)
    mvwaddstr(win, Int32(startRow), Int32(indent), "| \(emptyLine) |")
    startRow += 1

    for action in quickActions {
        drawMenuItem(win: win, row: startRow, indent: indent, menuWidth: menuWidth, key: action.key, cmd: action.cmd, desc: action.desc)
        startRow += 1
    }

    mvwaddstr(win, Int32(startRow), Int32(indent), "| \(emptyLine) |")
    startRow += 1

    for action in quickApps {
        drawMenuItem(win: win, row: startRow, indent: indent, menuWidth: menuWidth, key: action.key, cmd: action.cmd, desc: action.desc)
        startRow += 1
    }

    mvwaddstr(win, Int32(startRow), Int32(indent), "| \(emptyLine) |")
    startRow += 1
    mvwaddstr(win, Int32(startRow), Int32(indent), "+" + String(repeating: "-", count: menuWidth - 2) + "+")
    startRow += 1
}

private func drawMenuItem(win: OpaquePointer, row: Int, indent: Int, menuWidth: Int, key: String, cmd: String, desc: String) {
    mvwaddstr(win, Int32(row), Int32(indent), "|   ")
    wattron(win, COLOR_PAIR(6) | Int32(CURSES_A_BOLD))
    waddstr(win, "[\(key)]")
    wattroff(win, COLOR_PAIR(6) | Int32(CURSES_A_BOLD))
    wattron(win, COLOR_PAIR(2) | Int32(CURSES_A_BOLD))
    waddstr(win, " \(cmd.padding(toLength: 10, withPad: " ", startingAt: 0))")
    wattroff(win, COLOR_PAIR(2) | Int32(CURSES_A_BOLD))
    wattron(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))
    waddstr(win, " \(desc)")
    wattroff(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))

    // Pad to right border using actual cursor position
    let curX = Int(getcurx(win))
    let rightBorder = indent + menuWidth - 1
    let padding = max(0, rightBorder - curX - 1)
    waddstr(win, String(repeating: " ", count: padding))
    waddstr(win, "|")
}

private func drawTip(win: OpaquePointer, row: Int, cols: Int) {
    let tip = "Type any command or press a shortcut key"
    let indent = max(0, (cols - tip.count) / 2)
    wattron(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))
    mvwaddstr(win, Int32(row), Int32(indent), tip)
    wattroff(win, COLOR_PAIR(7) | Int32(CURSES_A_DIM))
}

// MARK: - REPL Drawing

private func drawScrollArea() {
    guard let win = scrollWin else { return }
    werase(win)

    let rows = Int(getmaxy(win))
    let cols = Int(getmaxx(win))
    let totalLines = scrollBuffer.count

    let visibleStart = max(0, totalLines - rows - scrollOffset)
    let visibleEnd = min(totalLines, visibleStart + rows)

    for i in visibleStart..<visibleEnd {
        let line = scrollBuffer[i]
        let row = Int32(i - visibleStart)
        if line.isCommand {
            wattron(win, COLOR_PAIR(2) | Int32(CURSES_A_BOLD))
            mvwaddstr(win, row, 0, String(line.text.prefix(cols)))
            wattroff(win, COLOR_PAIR(2) | Int32(CURSES_A_BOLD))
        } else {
            wattron(win, COLOR_PAIR(3))
            mvwaddstr(win, row, 0, String(line.text.prefix(cols)))
            wattroff(win, COLOR_PAIR(3))
        }
    }

    wrefresh(win)
}

private func drawInput() {
    guard let win = inputWin else { return }
    werase(win)
    let prompt = "swiss> "
    wattron(win, COLOR_PAIR(2) | Int32(CURSES_A_BOLD))
    mvwaddstr(win, 0, 0, prompt)
    wattroff(win, COLOR_PAIR(2) | Int32(CURSES_A_BOLD))
    waddstr(win, inputBuffer)
    wmove(win, 0, Int32(prompt.count + cursorPos))
    curs_set(1)
    wrefresh(win)
}

private func drawStatusBar() {
    guard let win = statusWin else { return }
    werase(win)
    wbkgd(win, UInt32(COLOR_PAIR(4)))

    let (pct, charging) = cachedBattery
    let batIcon = charging ? "+" : ""
    let bat = "bat:\(pct)%\(batIcon)"
    let wifi = "WiFi:\(cachedWifi.prefix(12))"
    let disk = "Disk:\(cachedDiskFree)GB"
    let quit = "q:quit"

    mvwaddstr(win, 0, 0, " \(bat) | \(wifi) | \(disk) | \(quit)")
    wrefresh(win)
}

// MARK: - Keypress Handling

private func tuiHandleKeypress(_ ch: Int32) {
    switch tuiMode {
    case .welcome:
        tuiHandleWelcomeKey(ch)
    case .repl:
        tuiHandleReplKey(ch)
    }
}

private func tuiHandleWelcomeKey(_ ch: Int32) {
    switch ch {
    case 3: // Ctrl+C
        shouldQuit = true
    case 10, 13: // Enter
        if !inputBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
            tuiMode = .repl
            tuiExecuteInput()
        }
    case 127, Int32(KEY_BACKSPACE):
        tuiHandleBackspace()
    case Int32(KEY_RESIZE):
        tuiHandleResize()
    default:
        if let cmd = tuiMatchQuickAction(ch) {
            if cmd == "quit" {
                shouldQuit = true
            } else {
                tuiMode = .repl
                inputBuffer = ""
                cursorPos = 0
                tuiRunQuickAction(cmd)
            }
        } else {
            tuiInsertChar(ch)
        }
    }
}

private func tuiMatchQuickAction(_ ch: Int32) -> String? {
    guard inputBuffer.isEmpty, ch >= 32 && ch < 127 else { return nil }
    guard let scalar = UnicodeScalar(UInt32(ch)) else { return nil }
    let key = String(Character(scalar))

    for action in quickActions where action.key == key {
        return action.cmd
    }
    for action in quickApps where action.key == key {
        return action.cmd
    }
    if key == "q" { return "quit" }
    return nil
}

private func tuiRunQuickAction(_ cmd: String) {
    scrollBuffer.append(TUILine(text: "> \(cmd)", isCommand: true))
    scrollOffset = 0

    if terminalTakeoverCommands.contains(cmd) {
        tuiExecExternal(cmd, args: [])
        drawAll()
        return
    }

    tuiRunAndDisplay(cmd, args: [])
}

private func tuiHandleReplKey(_ ch: Int32) {
    switch ch {
    case 3: // Ctrl+C
        shouldQuit = true
    case 10, 13:
        tuiExecuteInput()
    case 127, Int32(KEY_BACKSPACE):
        tuiHandleBackspace()
    case Int32(KEY_UP):
        tuiHistoryUp()
    case Int32(KEY_DOWN):
        tuiHistoryDown()
    case 9: // Tab
        tuiHandleTab()
    case Int32(KEY_PPAGE):
        tuiScrollUp(lines: Int(LINES) - 4)
    case Int32(KEY_NPAGE):
        tuiScrollDown(lines: Int(LINES) - 4)
    case Int32(KEY_RESIZE):
        tuiHandleResize()
    case Int32(KEY_LEFT):
        if cursorPos > 0 { cursorPos -= 1; drawInput() }
    case Int32(KEY_RIGHT):
        if cursorPos < inputBuffer.count { cursorPos += 1; drawInput() }
    default:
        tuiInsertChar(ch)
    }
}

// MARK: - Command Execution (subprocess-based, safe from exit() crashes)

private func tuiExecuteInput() {
    let input = inputBuffer.trimmingCharacters(in: .whitespaces)
    inputBuffer = ""
    cursorPos = 0
    historyIndex = -1

    guard !input.isEmpty else { drawInput(); return }

    if commandHistory.last != input {
        commandHistory.append(input)
        saveHistoryLine(input)
    }

    scrollBuffer.append(TUILine(text: "> \(input)", isCommand: true))
    scrollOffset = 0

    let parts = input.components(separatedBy: " ").filter { !$0.isEmpty }
    let cmd = parts[0]
    let cmdArgs = Array(parts.dropFirst())

    switch cmd {
    case "quit", "exit":
        shouldQuit = true
        return
    case "clear", "home", "menu", "back", "welcome":
        scrollBuffer.removeAll()
        scrollOffset = 0
        tuiMode = .welcome
        tuiRefreshSystemInfo()
        drawAll()
        return
    default:
        break
    }

    if terminalTakeoverCommands.contains(cmd) {
        tuiExecExternal(cmd, args: cmdArgs)
        drawAll()
        return
    }

    tuiRunAndDisplay(cmd, args: cmdArgs)
}

/// Runs a swiss command as a subprocess. This isolates the TUI from exit() calls,
/// global state changes, and crashed commands.
private func tuiRunAndDisplay(_ cmd: String, args: [String]) {
    let process = Process()
    let outPipe = Pipe()
    let errPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: swissBinary)
    process.arguments = [cmd] + args
    process.standardOutput = outPipe
    process.standardError = errPipe

    var outData = Data()
    var errData = Data()
    let group = DispatchGroup()

    group.enter()
    DispatchQueue.global().async {
        outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    group.enter()
    DispatchQueue.global().async {
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        scrollBuffer.append(TUILine(text: "Error: \(error.localizedDescription)", isCommand: false))
    }

    group.wait()

    let output = (String(data: outData, encoding: .utf8) ?? "")
                + (String(data: errData, encoding: .utf8) ?? "")
    for line in output.components(separatedBy: "\n") where !line.isEmpty {
        let truncated = line.count > 4096 ? String(line.prefix(4096)) + "..." : line
        scrollBuffer.append(TUILine(text: truncated, isCommand: false))
    }
    scrollBuffer.append(TUILine(text: "", isCommand: false))
    tuiTrimScrollBuffer()

    drawScrollArea()
    drawInput()
}

// MARK: - Terminal Takeover Commands

private func tuiExecExternal(_ cmd: String, args: [String]) {
    endwin()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    switch cmd {
    case "rss":
        process.arguments = ["newsboat"] + args
    case "dua":
        let duaArgs = args.isEmpty ? ["interactive", NSHomeDirectory()] : args
        process.arguments = ["dua"] + duaArgs
    case "top":
        process.arguments = ["btm"] + args
    default:
        refresh(); setupWindows(); return
    }

    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    do {
        try process.run()
        process.waitUntilExit()
        scrollBuffer.append(TUILine(text: "(\(cmd) exited)", isCommand: false))
    } catch {
        scrollBuffer.append(TUILine(text: "Error launching \(cmd): \(error.localizedDescription)", isCommand: false))
    }
    scrollBuffer.append(TUILine(text: "", isCommand: false))

    refresh()
    setupWindows()
}

// MARK: - Input Handling

private func tuiInsertChar(_ ch: Int32) {
    guard ch >= 32 && ch < 127,
          let scalar = UnicodeScalar(UInt32(ch)) else { return }
    let char = Character(scalar)
    let idx = inputBuffer.index(inputBuffer.startIndex, offsetBy: cursorPos)
    inputBuffer.insert(char, at: idx)
    cursorPos += 1
    drawInput()
}

private func tuiHandleBackspace() {
    guard cursorPos > 0 else { return }
    let idx = inputBuffer.index(inputBuffer.startIndex, offsetBy: cursorPos - 1)
    inputBuffer.remove(at: idx)
    cursorPos -= 1
    drawInput()
}

private func tuiHistoryUp() {
    guard !commandHistory.isEmpty else { return }
    if historyIndex < 0 {
        historyIndex = commandHistory.count - 1
    } else if historyIndex > 0 {
        historyIndex -= 1
    }
    inputBuffer = commandHistory[historyIndex]
    cursorPos = inputBuffer.count
    drawInput()
}

private func tuiHistoryDown() {
    guard historyIndex >= 0 else { return }
    if historyIndex < commandHistory.count - 1 {
        historyIndex += 1
        inputBuffer = commandHistory[historyIndex]
    } else {
        historyIndex = -1
        inputBuffer = ""
    }
    cursorPos = inputBuffer.count
    drawInput()
}

private func tuiHandleTab() {
    let prefix = inputBuffer.trimmingCharacters(in: .whitespaces)
    guard !prefix.isEmpty else { return }

    let parts = prefix.components(separatedBy: " ")
    guard parts.count == 1 else { return }

    let matches = tuiCommands.filter { $0.hasPrefix(prefix) }
    if matches.count == 1 {
        inputBuffer = matches[0] + " "
        cursorPos = inputBuffer.count
        drawInput()
    } else if matches.count > 1 {
        scrollBuffer.append(TUILine(text: matches.joined(separator: "  "), isCommand: false))
        drawScrollArea()
        drawInput()
    }
}

// MARK: - Scrolling

private func tuiScrollUp(lines: Int) {
    guard let win = scrollWin else { return }
    let maxOffset = max(0, scrollBuffer.count - Int(getmaxy(win)))
    scrollOffset = min(scrollOffset + lines, maxOffset)
    drawScrollArea()
    drawInput()
}

private func tuiScrollDown(lines: Int) {
    scrollOffset = max(0, scrollOffset - lines)
    drawScrollArea()
    drawInput()
}

private func tuiTrimScrollBuffer() {
    if scrollBuffer.count > maxScrollBuffer {
        scrollBuffer.removeFirst(scrollBuffer.count - maxScrollBuffer)
    }
}

// MARK: - Resize

private func tuiHandleResize() {
    endwin()
    refresh()

    if LINES < minRows || COLS < minCols {
        setupWindows()
        guard let win = scrollWin else { return }
        werase(win)
        mvwaddstr(win, 0, 0, "Terminal too small")
        wrefresh(win)
        drawInput()
        return
    }

    setupWindows()
    drawAll()
}

// MARK: - History Persistence

private func loadHistory() {
    guard let content = try? String(contentsOfFile: historyFile, encoding: .utf8) else { return }
    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    commandHistory = Array(lines.suffix(500))
}

private func saveHistoryLine(_ line: String) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: historyFile) {
        if let handle = FileHandle(forWritingAtPath: historyFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        FileManager.default.createFile(atPath: historyFile, contents: data)
    }
}

// MARK: - Cleanup

private func tuiCleanup() {
    curs_set(1)
    endwin()
}
