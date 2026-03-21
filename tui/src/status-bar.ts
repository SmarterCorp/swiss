import { Text } from "@opentui/core"
import { colors } from "./colors"
import type { SystemInfo } from "./system-info"

export function createStatusBarTexts(info: SystemInfo) {
  const { percent, charging } = info.battery
  const batIcon = charging ? "+" : ""

  return [
    Text({ content: `  bat ${percent}%${batIcon} | ${info.wifi.slice(0, 12)} | ${info.diskFreeGB}GB free`, fg: colors.textSecondary }),
  ]
}
