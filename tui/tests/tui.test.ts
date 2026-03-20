import { describe, test, expect, mock, spyOn } from "bun:test"
import { colors } from "../src/colors"
import { version } from "../src/version"
import type { SystemInfo } from "../src/system-info"

// ============================================================
// colors.ts
// ============================================================

function isValidHex(c: string) {
  return /^#[0-9a-fA-F]{6}$/.test(c)
}

function brightness(hex: string) {
  return parseInt(hex.slice(1, 3), 16) + parseInt(hex.slice(3, 5), 16) + parseInt(hex.slice(5, 7), 16)
}

describe("colors", () => {
  test("all values are valid hex", () => {
    for (const value of Object.values(colors)) {
      expect(isValidHex(value)).toBe(true)
    }
  })

  test("has all required keys", () => {
    const required = [
      "bg", "bgSurface", "bgHighlight", "accent", "accentBright",
      "secondary", "textBright", "textNormal", "textSecondary",
      "textDim", "textMuted", "success", "error",
    ]
    for (const key of required) {
      expect(colors).toHaveProperty(key)
    }
  })

  test("backgrounds are ordered dark to light", () => {
    expect(brightness(colors.bg)).toBeLessThan(brightness(colors.bgSurface))
    expect(brightness(colors.bgSurface)).toBeLessThan(brightness(colors.bgHighlight))
  })

  test("text hierarchy brightness order", () => {
    expect(brightness(colors.textBright)).toBeGreaterThan(brightness(colors.textNormal))
    expect(brightness(colors.textNormal)).toBeGreaterThan(brightness(colors.textSecondary))
    expect(brightness(colors.textSecondary)).toBeGreaterThan(brightness(colors.textDim))
    expect(brightness(colors.textDim)).toBeGreaterThan(brightness(colors.textMuted))
  })

  test("no duplicate background values", () => {
    const bgs = [colors.bg, colors.bgSurface, colors.bgHighlight]
    expect(new Set(bgs).size).toBe(3)
  })

  test("accent is warm (r > g > b)", () => {
    const r = parseInt(colors.accent.slice(1, 3), 16)
    const g = parseInt(colors.accent.slice(3, 5), 16)
    const b = parseInt(colors.accent.slice(5, 7), 16)
    expect(r).toBeGreaterThan(g)
    expect(g).toBeGreaterThan(b)
  })

  test("success is green-ish", () => {
    const g = parseInt(colors.success.slice(3, 5), 16)
    expect(g).toBeGreaterThan(parseInt(colors.success.slice(1, 3), 16))
  })

  test("error is red-ish", () => {
    const r = parseInt(colors.error.slice(1, 3), 16)
    expect(r).toBeGreaterThan(parseInt(colors.error.slice(3, 5), 16))
  })
})

// ============================================================
// version.ts
// ============================================================

describe("version", () => {
  test("matches semver format", () => {
    expect(version).toMatch(/^\d+\.\d+\.\d+$/)
  })

  test("is 1.7.0", () => {
    expect(version).toBe("1.7.0")
  })
})

// ============================================================
// welcome.ts — createWelcomeLines returns VNode array
// ============================================================

import { createWelcomeLines } from "../src/welcome"

describe("createWelcomeLines", () => {
  const info: SystemInfo = {
    battery: { percent: 85, charging: true },
    wifi: "TestNet",
    diskFreeGB: 100,
  }

  const infoLow: SystemInfo = {
    battery: { percent: 10, charging: false },
    wifi: "disconnected",
    diskFreeGB: 0,
  }

  test("returns non-empty array", () => {
    const lines = createWelcomeLines(info)
    expect(Array.isArray(lines)).toBe(true)
    expect(lines.length).toBeGreaterThan(10)
  })

  test("returns same structure for different inputs", () => {
    const a = createWelcomeLines(info)
    const b = createWelcomeLines(infoLow)
    expect(a.length).toBe(b.length)
  })

  test("all elements are VNode-like objects", () => {
    const lines = createWelcomeLines(info)
    for (const line of lines) {
      expect(line).toBeDefined()
      expect(typeof line).toBe("object")
    }
  })

  test("works with zero battery", () => {
    const lines = createWelcomeLines({ battery: { percent: 0, charging: false }, wifi: "", diskFreeGB: 0 })
    expect(lines.length).toBeGreaterThan(0)
  })

  test("works with 100% battery charging", () => {
    const lines = createWelcomeLines({ battery: { percent: 100, charging: true }, wifi: "X", diskFreeGB: 999 })
    expect(lines.length).toBeGreaterThan(0)
  })
})

// ============================================================
// status-bar.ts — createStatusBarTexts returns VNode array
// ============================================================

import { createStatusBarTexts } from "../src/status-bar"

describe("createStatusBarTexts", () => {
  const info: SystemInfo = {
    battery: { percent: 80, charging: true },
    wifi: "HomeNet",
    diskFreeGB: 50,
  }

  test("returns non-empty array", () => {
    const texts = createStatusBarTexts(info)
    expect(Array.isArray(texts)).toBe(true)
    expect(texts.length).toBeGreaterThan(0)
  })

  test("returns 7 elements (bat, sep, wifi, sep, disk, sep, quit)", () => {
    const texts = createStatusBarTexts(info)
    expect(texts.length).toBe(7)
  })

  test("works with not charging", () => {
    const texts = createStatusBarTexts({ battery: { percent: 42, charging: false }, wifi: "X", diskFreeGB: 10 })
    expect(texts.length).toBe(7)
  })

  test("works with long wifi name (truncated to 12)", () => {
    const texts = createStatusBarTexts({ battery: { percent: 50, charging: false }, wifi: "VeryLongNetworkName", diskFreeGB: 10 })
    expect(texts.length).toBe(7)
  })

  test("works with empty wifi", () => {
    const texts = createStatusBarTexts({ battery: { percent: 50, charging: false }, wifi: "", diskFreeGB: 0 })
    expect(texts.length).toBe(7)
  })
})

// ============================================================
// system-info.ts — getSystemInfo
// ============================================================

import { getSystemInfo } from "../src/system-info"

describe("getSystemInfo", () => {
  test("returns SystemInfo shape", async () => {
    const info = await getSystemInfo()
    expect(info).toHaveProperty("battery")
    expect(info).toHaveProperty("wifi")
    expect(info).toHaveProperty("diskFreeGB")
    expect(info.battery).toHaveProperty("percent")
    expect(info.battery).toHaveProperty("charging")
  })

  test("battery percent is a number >= 0", async () => {
    const info = await getSystemInfo()
    expect(typeof info.battery.percent).toBe("number")
    expect(info.battery.percent).toBeGreaterThanOrEqual(0)
  })

  test("wifi is a string", async () => {
    const info = await getSystemInfo()
    expect(typeof info.wifi).toBe("string")
  })

  test("diskFreeGB is a number >= 0", async () => {
    const info = await getSystemInfo()
    expect(typeof info.diskFreeGB).toBe("number")
    expect(info.diskFreeGB).toBeGreaterThanOrEqual(0)
  })
})

// ============================================================
// swiss.ts — runSwissCommand
// ============================================================

import { runSwissCommand } from "../src/swiss"

describe("runSwissCommand", () => {
  test("runs version command", async () => {
    const output = await runSwissCommand("version")
    expect(output).toContain("swiss")
  })

  test("runs help command", async () => {
    const output = await runSwissCommand("help")
    expect(output.length).toBeGreaterThan(0)
  })

  test("empty input returns empty", async () => {
    const output = await runSwissCommand("")
    expect(output).toBe("")
  })

  test("unknown command returns error output", async () => {
    const output = await runSwissCommand("nonexistent_cmd_xyz")
    // swiss prints error to stderr which gets captured
    expect(typeof output).toBe("string")
  })

  test("command with args works", async () => {
    const output = await runSwissCommand("battery --json")
    expect(typeof output).toBe("string")
    expect(output.length).toBeGreaterThan(0)
  })
})
