import { Box, Text } from "@opentui/core"
import { colors } from "./colors"
import type { SystemInfo } from "./system-info"
import { version } from "./version"

const logo = [
  " ____ _    _ _ ____ ____",
  "| ___| |  | | | ___| ___|",
  "|___ |  V V  | |___ |___ |",
  "|____|  V V  |_|____|____|",
]

const commandGroups = [
  { cat: "Status",      cmds: ["battery", "wifi", "ports", "usb", "status", "dash"] },
  { cat: "Utilities",   cmds: ["clipboard", "prompt", "pass", "translate"] },
  { cat: "Switchers",   cmds: ["display", "cursor", "sleep", "menubar"] },
  { cat: "Maintenance", cmds: ["install", "clean", "maintain"] },
  { cat: "Apps",        cmds: ["textream", "twitter", "rss", "dua", "top"] },
]

export function createWelcomeLines(info: SystemInfo) {
  const { percent, charging } = info.battery
  const batStatus = charging ? `${percent}% charging` : `${percent}%`
  const batColor = percent > 20 ? colors.success : colors.error

  const lines: Array<{ content: string; fg: string; bold?: boolean }> = []

  // Logo
  for (const line of logo) {
    lines.push({ content: `  ${line}`, fg: colors.accent, bold: true })
  }
  lines.push({ content: `  v${version}`, fg: colors.textDim })
  lines.push({ content: " ", fg: colors.textDim })

  // System info
  lines.push({ content: `  Battery     ${batStatus}`, fg: batColor })
  lines.push({ content: `  WiFi        ${info.wifi}`, fg: colors.textNormal })
  lines.push({ content: `  Disk        ${info.diskFreeGB} GB free`, fg: colors.textNormal })
  lines.push({ content: " ", fg: colors.textDim })

  // Commands
  lines.push({ content: "  Commands", fg: colors.textSecondary, bold: true })
  for (const g of commandGroups) {
    lines.push({
      content: `  ${g.cat.padEnd(14)}${g.cmds.join("  ")}`,
      fg: colors.textNormal,
    })
  }
  lines.push({ content: " ", fg: colors.textDim })

  // Tips
  lines.push({ content: "  Tips", fg: colors.textSecondary, bold: true })
  lines.push({ content: "  Type any command name and press Enter", fg: colors.textDim })
  lines.push({ content: "  'home', 'menu', 'back', 'clear' to return here", fg: colors.textDim })
  lines.push({ content: "  'q', 'quit', or ctrl+c to exit", fg: colors.textDim })

  return lines.map(l =>
    Box({ width: "100%", height: 1 },
      Text({ content: l.content, fg: l.fg, bold: l.bold })
    )
  )
}
