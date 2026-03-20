import { describe, test, expect } from "bun:test"
import { colors } from "../src/colors"
import { version } from "../src/version"
import {
  parseCommandParts,
  buildQuickActionMap,
  parseSystemInfo,
  fallbackSystemInfo,
  formatBatteryStatus,
  batteryColor,
  formatInfoLabel,
  formatActionRow,
  formatStatusBar,
  headerBrand,
  formatCommandLine,
  formatOutputLine,
  formatOutputLines,
  isExitCommand,
  isClearCommand,
  isValidHexColor,
  processInput,
  isKnownCommand,
  swissCommands,
  type QuickAction,
  type SystemInfo,
} from "../src/logic"

// ============================================================
// 1. Colors
// ============================================================

describe("colors", () => {
  test("1: all color values are valid hex", () => {
    for (const [key, value] of Object.entries(colors)) {
      expect(isValidHexColor(value)).toBe(true)
    }
  })

  test("2: bg is near-black", () => {
    expect(colors.bg).toBe("#121212")
  })

  test("3: bgSurface is slightly lighter than bg", () => {
    const bgVal = parseInt(colors.bg.slice(1), 16)
    const surfVal = parseInt(colors.bgSurface.slice(1), 16)
    expect(surfVal).toBeGreaterThan(bgVal)
  })

  test("4: accent is warm amber tone", () => {
    const r = parseInt(colors.accent.slice(1, 3), 16)
    const g = parseInt(colors.accent.slice(3, 5), 16)
    const b = parseInt(colors.accent.slice(5, 7), 16)
    expect(r).toBeGreaterThan(g)
    expect(g).toBeGreaterThan(b)
  })

  test("5: text hierarchy brightness order", () => {
    const brightness = (hex: string) => {
      const r = parseInt(hex.slice(1, 3), 16)
      const g = parseInt(hex.slice(3, 5), 16)
      const b = parseInt(hex.slice(5, 7), 16)
      return r + g + b
    }
    expect(brightness(colors.textBright)).toBeGreaterThan(brightness(colors.textNormal))
    expect(brightness(colors.textNormal)).toBeGreaterThan(brightness(colors.textSecondary))
    expect(brightness(colors.textSecondary)).toBeGreaterThan(brightness(colors.textDim))
    expect(brightness(colors.textDim)).toBeGreaterThan(brightness(colors.textMuted))
  })

  test("6: success is green-ish", () => {
    const g = parseInt(colors.success.slice(3, 5), 16)
    const r = parseInt(colors.success.slice(1, 3), 16)
    const b = parseInt(colors.success.slice(5, 7), 16)
    expect(g).toBeGreaterThan(r)
    expect(g).toBeGreaterThan(b)
  })

  test("7: error is red-ish", () => {
    const r = parseInt(colors.error.slice(1, 3), 16)
    const g = parseInt(colors.error.slice(3, 5), 16)
    const b = parseInt(colors.error.slice(5, 7), 16)
    expect(r).toBeGreaterThan(g)
    expect(r).toBeGreaterThan(b)
  })

  test("8: has all required color keys", () => {
    const required = [
      "bg", "bgSurface", "bgHighlight", "accent", "accentBright",
      "secondary", "textBright", "textNormal", "textSecondary",
      "textDim", "textMuted", "success", "error",
    ]
    for (const key of required) {
      expect(colors).toHaveProperty(key)
    }
  })

  test("9: no duplicate color values in backgrounds", () => {
    const bgs = [colors.bg, colors.bgSurface, colors.bgHighlight]
    expect(new Set(bgs).size).toBe(bgs.length)
  })

  test("10: bgHighlight brighter than bgSurface", () => {
    const surfVal = parseInt(colors.bgSurface.slice(1), 16)
    const highVal = parseInt(colors.bgHighlight.slice(1), 16)
    expect(highVal).toBeGreaterThan(surfVal)
  })
})

// ============================================================
// 2. Version
// ============================================================

describe("version", () => {
  test("11: version is a string", () => {
    expect(typeof version).toBe("string")
  })

  test("12: version matches semver format", () => {
    expect(version).toMatch(/^\d+\.\d+\.\d+$/)
  })

  test("13: version is 1.7.0", () => {
    expect(version).toBe("1.7.0")
  })
})

// ============================================================
// 3. Command Parsing
// ============================================================

describe("parseCommandParts", () => {
  test("14: simple command", () => {
    expect(parseCommandParts("battery")).toEqual(["battery"])
  })

  test("15: command with args", () => {
    expect(parseCommandParts("display off")).toEqual(["display", "off"])
  })

  test("16: extra whitespace is trimmed", () => {
    expect(parseCommandParts("  battery  --json  ")).toEqual(["battery", "--json"])
  })

  test("17: empty string returns empty array", () => {
    expect(parseCommandParts("")).toEqual([])
  })

  test("18: only whitespace returns empty array", () => {
    expect(parseCommandParts("   ")).toEqual([])
  })

  test("19: tabs are treated as separators", () => {
    expect(parseCommandParts("wifi\t--json")).toEqual(["wifi", "--json"])
  })

  test("20: single char command", () => {
    expect(parseCommandParts("q")).toEqual(["q"])
  })

  test("21: many args", () => {
    expect(parseCommandParts("a b c d e")).toEqual(["a", "b", "c", "d", "e"])
  })

  test("22: newlines in input are split", () => {
    expect(parseCommandParts("a\nb")).toEqual(["a", "b"])
  })

  test("23: mixed whitespace types", () => {
    expect(parseCommandParts(" a \t b \n c ")).toEqual(["a", "b", "c"])
  })
})

// ============================================================
// 4. Quick Action Map
// ============================================================

describe("buildQuickActionMap", () => {
  const actions: QuickAction[] = [
    { key: "1", cmd: "dash", desc: "Dashboard" },
    { key: "2", cmd: "status", desc: "Status" },
    { key: "r", cmd: "rss", desc: "RSS" },
  ]

  test("24: maps keys to commands", () => {
    const map = buildQuickActionMap(actions)
    expect(map["1"]).toBe("dash")
    expect(map["2"]).toBe("status")
    expect(map["r"]).toBe("rss")
  })

  test("25: empty array returns empty map", () => {
    expect(buildQuickActionMap([])).toEqual({})
  })

  test("26: last duplicate key wins", () => {
    const dup: QuickAction[] = [
      { key: "1", cmd: "first", desc: "" },
      { key: "1", cmd: "second", desc: "" },
    ]
    expect(buildQuickActionMap(dup)["1"]).toBe("second")
  })

  test("27: non-existent key returns undefined", () => {
    const map = buildQuickActionMap(actions)
    expect(map["z"]).toBeUndefined()
  })

  test("28: map size matches input", () => {
    const map = buildQuickActionMap(actions)
    expect(Object.keys(map).length).toBe(3)
  })

  test("29: preserves original command strings", () => {
    const special: QuickAction[] = [{ key: "x", cmd: "some-cmd --flag", desc: "" }]
    expect(buildQuickActionMap(special)["x"]).toBe("some-cmd --flag")
  })
})

// ============================================================
// 5. System Info Parsing
// ============================================================

describe("parseSystemInfo", () => {
  const fullJson = {
    system: {
      battery_percent: 85,
      battery_charging: true,
      network_ssid: "MyWiFi",
      disk_free_bytes: 107374182400, // 100 GB
    },
  }

  test("30: parses battery percent", () => {
    expect(parseSystemInfo(fullJson).battery.percent).toBe(85)
  })

  test("31: parses battery charging", () => {
    expect(parseSystemInfo(fullJson).battery.charging).toBe(true)
  })

  test("32: parses wifi ssid", () => {
    expect(parseSystemInfo(fullJson).wifi).toBe("MyWiFi")
  })

  test("33: parses disk free in GB", () => {
    expect(parseSystemInfo(fullJson).diskFreeGB).toBe(100)
  })

  test("34: missing system key returns defaults", () => {
    const info = parseSystemInfo({})
    expect(info.battery.percent).toBe(0)
    expect(info.battery.charging).toBe(false)
    expect(info.wifi).toBe("disconnected")
    expect(info.diskFreeGB).toBe(0)
  })

  test("35: null input returns defaults", () => {
    const info = parseSystemInfo(null)
    expect(info.battery.percent).toBe(0)
  })

  test("36: undefined input returns defaults", () => {
    const info = parseSystemInfo(undefined)
    expect(info.wifi).toBe("disconnected")
  })

  test("37: partial system data fills defaults", () => {
    const info = parseSystemInfo({ system: { battery_percent: 50 } })
    expect(info.battery.percent).toBe(50)
    expect(info.battery.charging).toBe(false)
    expect(info.wifi).toBe("disconnected")
    expect(info.diskFreeGB).toBe(0)
  })

  test("38: zero battery percent", () => {
    const info = parseSystemInfo({ system: { battery_percent: 0 } })
    expect(info.battery.percent).toBe(0)
  })

  test("39: disk rounds correctly", () => {
    // 1.5 GB
    const info = parseSystemInfo({ system: { disk_free_bytes: 1610612736 } })
    expect(info.diskFreeGB).toBe(2)
  })

  test("40: disk rounds down for small fractions", () => {
    // 0.4 GB
    const info = parseSystemInfo({ system: { disk_free_bytes: 429496729 } })
    expect(info.diskFreeGB).toBe(0)
  })

  test("41: zero disk_free_bytes", () => {
    const info = parseSystemInfo({ system: { disk_free_bytes: 0 } })
    expect(info.diskFreeGB).toBe(0)
  })

  test("42: very large disk value", () => {
    // 2 TB
    const info = parseSystemInfo({ system: { disk_free_bytes: 2199023255552 } })
    expect(info.diskFreeGB).toBe(2048)
  })
})

describe("fallbackSystemInfo", () => {
  test("43: returns zero battery", () => {
    expect(fallbackSystemInfo().battery.percent).toBe(0)
  })

  test("44: returns not charging", () => {
    expect(fallbackSystemInfo().battery.charging).toBe(false)
  })

  test("45: returns unknown wifi", () => {
    expect(fallbackSystemInfo().wifi).toBe("unknown")
  })

  test("46: returns zero disk", () => {
    expect(fallbackSystemInfo().diskFreeGB).toBe(0)
  })
})

// ============================================================
// 6. Battery Formatting
// ============================================================

describe("formatBatteryStatus", () => {
  test("47: charging shows percentage with charging", () => {
    expect(formatBatteryStatus(85, true)).toBe("85% charging")
  })

  test("48: not charging shows only percentage", () => {
    expect(formatBatteryStatus(42, false)).toBe("42%")
  })

  test("49: zero percent charging", () => {
    expect(formatBatteryStatus(0, true)).toBe("0% charging")
  })

  test("50: 100 percent not charging", () => {
    expect(formatBatteryStatus(100, false)).toBe("100%")
  })
})

describe("batteryColor", () => {
  test("51: above 20 returns success color", () => {
    expect(batteryColor(21)).toBe(colors.success)
  })

  test("52: at 20 returns error color", () => {
    expect(batteryColor(20)).toBe(colors.error)
  })

  test("53: at 0 returns error color", () => {
    expect(batteryColor(0)).toBe(colors.error)
  })

  test("54: at 100 returns success color", () => {
    expect(batteryColor(100)).toBe(colors.success)
  })

  test("55: at 21 boundary returns success", () => {
    expect(batteryColor(21)).toBe(colors.success)
  })

  test("56: at 19 returns error", () => {
    expect(batteryColor(19)).toBe(colors.error)
  })
})

// ============================================================
// 7. Info & Action Row Formatting
// ============================================================

describe("formatInfoLabel", () => {
  test("57: pads short label to 13 chars", () => {
    expect(formatInfoLabel("WiFi")).toBe("  WiFi         ")
  })

  test("58: pads Battery label", () => {
    expect(formatInfoLabel("Battery")).toBe("  Battery      ")
  })

  test("59: exact 13-char label not truncated", () => {
    expect(formatInfoLabel("1234567890123")).toBe("  1234567890123")
  })

  test("60: empty label pads to 13 spaces", () => {
    expect(formatInfoLabel("")).toBe("  " + " ".repeat(13))
  })

  test("61: starts with 2-space indent", () => {
    expect(formatInfoLabel("X").startsWith("  ")).toBe(true)
  })
})

describe("formatActionRow", () => {
  test("62: formats key and cmd with padding", () => {
    expect(formatActionRow("1", "dash")).toBe("  1  dash        ")
  })

  test("63: long command pads to 12", () => {
    expect(formatActionRow("r", "rss")).toBe("  r  rss         ")
  })

  test("64: 12-char command no extra pad", () => {
    expect(formatActionRow("x", "123456789012")).toBe("  x  123456789012")
  })

  test("65: starts with 2-space indent", () => {
    expect(formatActionRow("k", "cmd").startsWith("  ")).toBe(true)
  })

  test("66: key is followed by 2 spaces", () => {
    const result = formatActionRow("a", "test")
    expect(result).toContain("  a  ")
  })
})

// ============================================================
// 8. Status Bar Formatting
// ============================================================

describe("formatStatusBar", () => {
  test("67: battery with charging icon", () => {
    const info: SystemInfo = { battery: { percent: 80, charging: true }, wifi: "Net", diskFreeGB: 50 }
    expect(formatStatusBar(info).battery).toBe("bat 80% +")
  })

  test("68: battery without charging icon", () => {
    const info: SystemInfo = { battery: { percent: 42, charging: false }, wifi: "Net", diskFreeGB: 50 }
    expect(formatStatusBar(info).battery).toBe("bat 42%")
  })

  test("69: wifi truncated to 12 chars", () => {
    const info: SystemInfo = { battery: { percent: 50, charging: false }, wifi: "VeryLongNetworkName", diskFreeGB: 10 }
    expect(formatStatusBar(info).wifi).toBe("VeryLongNetw")
    expect(formatStatusBar(info).wifi.length).toBeLessThanOrEqual(12)
  })

  test("70: short wifi not truncated", () => {
    const info: SystemInfo = { battery: { percent: 50, charging: false }, wifi: "Home", diskFreeGB: 10 }
    expect(formatStatusBar(info).wifi).toBe("Home")
  })

  test("71: disk format", () => {
    const info: SystemInfo = { battery: { percent: 50, charging: false }, wifi: "x", diskFreeGB: 247 }
    expect(formatStatusBar(info).disk).toBe("247GB free")
  })

  test("72: zero disk", () => {
    const info: SystemInfo = { battery: { percent: 0, charging: false }, wifi: "x", diskFreeGB: 0 }
    expect(formatStatusBar(info).disk).toBe("0GB free")
  })

  test("73: empty wifi", () => {
    const info: SystemInfo = { battery: { percent: 50, charging: false }, wifi: "", diskFreeGB: 10 }
    expect(formatStatusBar(info).wifi).toBe("")
  })

  test("74: 100% battery", () => {
    const info: SystemInfo = { battery: { percent: 100, charging: false }, wifi: "x", diskFreeGB: 1 }
    expect(formatStatusBar(info).battery).toBe("bat 100%")
  })
})

// ============================================================
// 9. Header
// ============================================================

describe("headerBrand", () => {
  test("75: name starts with space", () => {
    expect(headerBrand().name).toBe(" swiss")
  })

  test("76: version includes v prefix", () => {
    expect(headerBrand().version).toMatch(/^ v\d+\.\d+\.\d+$/)
  })

  test("77: version matches current version", () => {
    expect(headerBrand().version).toBe(` v${version}`)
  })
})

// ============================================================
// 10. REPL Formatting
// ============================================================

describe("formatCommandLine", () => {
  test("78: formats with prompt prefix", () => {
    expect(formatCommandLine("battery")).toBe("  ❯ battery")
  })

  test("79: empty command", () => {
    expect(formatCommandLine("")).toBe("  ❯ ")
  })

  test("80: preserves args", () => {
    expect(formatCommandLine("display off")).toBe("  ❯ display off")
  })

  test("81: starts with 2-space indent", () => {
    expect(formatCommandLine("x").startsWith("  ")).toBe(true)
  })

  test("82: contains prompt character", () => {
    expect(formatCommandLine("x")).toContain("❯")
  })
})

describe("formatOutputLine", () => {
  test("83: indents with 4 spaces", () => {
    expect(formatOutputLine("hello")).toBe("    hello")
  })

  test("84: empty string becomes space", () => {
    expect(formatOutputLine("")).toBe("     ")
  })

  test("85: preserves content", () => {
    expect(formatOutputLine("Battery: 85%")).toBe("    Battery: 85%")
  })

  test("86: starts with 4-space indent", () => {
    expect(formatOutputLine("x").startsWith("    ")).toBe(true)
  })
})

describe("formatOutputLines", () => {
  test("87: splits multi-line output", () => {
    const lines = formatOutputLines("line1\nline2\nline3")
    expect(lines.length).toBe(3)
  })

  test("88: each line is indented", () => {
    const lines = formatOutputLines("a\nb")
    expect(lines[0]).toBe("    a")
    expect(lines[1]).toBe("    b")
  })

  test("89: empty lines become space", () => {
    const lines = formatOutputLines("a\n\nb")
    expect(lines[1]).toBe("     ")
  })

  test("90: single line output", () => {
    const lines = formatOutputLines("single")
    expect(lines).toEqual(["    single"])
  })

  test("91: empty output produces one line", () => {
    const lines = formatOutputLines("")
    expect(lines).toEqual(["     "])
  })

  test("92: trailing newline creates extra line", () => {
    const lines = formatOutputLines("a\n")
    expect(lines.length).toBe(2)
  })
})

// ============================================================
// 11. Command Classification
// ============================================================

describe("isExitCommand", () => {
  test("93: quit is exit", () => {
    expect(isExitCommand("quit")).toBe(true)
  })

  test("94: exit is exit", () => {
    expect(isExitCommand("exit")).toBe(true)
  })

  test("95: q is exit", () => {
    expect(isExitCommand("q")).toBe(true)
  })

  test("96: other commands are not exit", () => {
    expect(isExitCommand("battery")).toBe(false)
  })

  test("97: empty string is not exit", () => {
    expect(isExitCommand("")).toBe(false)
  })

  test("98: QUIT (uppercase) is not exit", () => {
    expect(isExitCommand("QUIT")).toBe(false)
  })
})

describe("isClearCommand", () => {
  test("99: clear is clear", () => {
    expect(isClearCommand("clear")).toBe(true)
  })

  test("100: home is clear", () => {
    expect(isClearCommand("home")).toBe(true)
  })

  test("101: other commands are not clear", () => {
    expect(isClearCommand("battery")).toBe(false)
  })

  test("102: CLEAR (uppercase) is not clear", () => {
    expect(isClearCommand("CLEAR")).toBe(false)
  })
})

// ============================================================
// 13. Input Processing (processInput)
// ============================================================

describe("processInput", () => {
  test("103: empty string returns noop", () => {
    expect(processInput("")).toEqual({ type: "noop" })
  })

  test("104: whitespace-only returns noop", () => {
    expect(processInput("   ")).toEqual({ type: "noop" })
  })

  test("105: quit returns exit", () => {
    expect(processInput("quit")).toEqual({ type: "exit" })
  })

  test("106: exit returns exit", () => {
    expect(processInput("exit")).toEqual({ type: "exit" })
  })

  test("107: q returns exit", () => {
    expect(processInput("q")).toEqual({ type: "exit" })
  })

  test("108: clear returns clear", () => {
    expect(processInput("clear")).toEqual({ type: "clear" })
  })

  test("109: home returns clear", () => {
    expect(processInput("home")).toEqual({ type: "clear" })
  })

  test("110: battery returns execute", () => {
    expect(processInput("battery")).toEqual({ type: "execute", cmd: "battery" })
  })

  test("111: dash returns execute", () => {
    expect(processInput("dash")).toEqual({ type: "execute", cmd: "dash" })
  })

  test("112: command with args returns execute with full string", () => {
    expect(processInput("display off")).toEqual({ type: "execute", cmd: "display off" })
  })

  test("113: trims whitespace before processing", () => {
    expect(processInput("  battery  ")).toEqual({ type: "execute", cmd: "battery" })
  })

  test("114: exit with extra spaces is trimmed to exit", () => {
    expect(processInput("  exit  ")).toEqual({ type: "exit" })
  })

  test("115: clear with spaces is trimmed to clear", () => {
    expect(processInput("  clear  ")).toEqual({ type: "clear" })
  })

  test("116: unknown command still returns execute", () => {
    expect(processInput("foobar")).toEqual({ type: "execute", cmd: "foobar" })
  })

  test("117: command with --json flag", () => {
    expect(processInput("dash --json")).toEqual({ type: "execute", cmd: "dash --json" })
  })

  test("118: single char non-exit command", () => {
    expect(processInput("x")).toEqual({ type: "execute", cmd: "x" })
  })
})

// ============================================================
// 14. Known Command Validation (isKnownCommand)
// ============================================================

describe("isKnownCommand", () => {
  test("119: battery is known", () => {
    expect(isKnownCommand("battery")).toBe(true)
  })

  test("120: dash is known", () => {
    expect(isKnownCommand("dash")).toBe(true)
  })

  test("121: wifi is known", () => {
    expect(isKnownCommand("wifi")).toBe(true)
  })

  test("122: ports is known", () => {
    expect(isKnownCommand("ports")).toBe(true)
  })

  test("123: usb is known", () => {
    expect(isKnownCommand("usb")).toBe(true)
  })

  test("124: status is known", () => {
    expect(isKnownCommand("status")).toBe(true)
  })

  test("125: clipboard is known", () => {
    expect(isKnownCommand("clipboard")).toBe(true)
  })

  test("126: display off — first word is known", () => {
    expect(isKnownCommand("display off")).toBe(true)
  })

  test("127: rss with args — first word is known", () => {
    expect(isKnownCommand("rss --help")).toBe(true)
  })

  test("128: unknown command", () => {
    expect(isKnownCommand("foobar")).toBe(false)
  })

  test("129: empty string is not known", () => {
    expect(isKnownCommand("")).toBe(false)
  })

  test("130: whitespace only is not known", () => {
    expect(isKnownCommand("   ")).toBe(false)
  })

  test("131: help is known", () => {
    expect(isKnownCommand("help")).toBe(true)
  })

  test("132: version is known", () => {
    expect(isKnownCommand("version")).toBe(true)
  })

  test("133: tui is known", () => {
    expect(isKnownCommand("tui")).toBe(true)
  })

  test("134: all swissCommands are known", () => {
    for (const cmd of swissCommands) {
      expect(isKnownCommand(cmd)).toBe(true)
    }
  })

  test("135: command with leading spaces", () => {
    expect(isKnownCommand("  battery")).toBe(true)
  })

  test("136: case sensitive — Battery is not known", () => {
    expect(isKnownCommand("Battery")).toBe(false)
  })
})

// ============================================================
// 15. Swiss Commands List
// ============================================================

describe("swissCommands", () => {
  test("137: is non-empty array", () => {
    expect(swissCommands.length).toBeGreaterThan(0)
  })

  test("138: contains core status commands", () => {
    expect(swissCommands).toContain("battery")
    expect(swissCommands).toContain("wifi")
    expect(swissCommands).toContain("dash")
  })

  test("139: contains utility commands", () => {
    expect(swissCommands).toContain("clipboard")
    expect(swissCommands).toContain("translate")
  })

  test("140: contains app commands", () => {
    expect(swissCommands).toContain("rss")
    expect(swissCommands).toContain("dua")
    expect(swissCommands).toContain("top")
  })

  test("141: no duplicates", () => {
    expect(new Set(swissCommands).size).toBe(swissCommands.length)
  })

  test("142: all entries are non-empty strings", () => {
    for (const cmd of swissCommands) {
      expect(typeof cmd).toBe("string")
      expect(cmd.length).toBeGreaterThan(0)
    }
  })
})

// ============================================================
// 12. Hex Color Validation
// ============================================================

describe("isValidHexColor", () => {
  test("valid 6-digit hex", () => {
    expect(isValidHexColor("#abcdef")).toBe(true)
  })

  test("invalid: no hash", () => {
    expect(isValidHexColor("abcdef")).toBe(false)
  })

  test("invalid: 3-digit shorthand", () => {
    expect(isValidHexColor("#abc")).toBe(false)
  })

  test("invalid: 8-digit with alpha", () => {
    expect(isValidHexColor("#abcdef00")).toBe(false)
  })
})
