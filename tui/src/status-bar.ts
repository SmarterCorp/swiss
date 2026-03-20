import { Text } from "@opentui/core"
import { colors } from "./colors"
import type { SystemInfo } from "./system-info"

export function createStatusBarTexts(info: SystemInfo) {
  const { percent, charging } = info.battery
  const batIcon = charging ? " +" : ""

  return [
    Text({ content: `  bat ${percent}%${batIcon}`, fg: colors.textSecondary }),
    Text({ content: "  │  ", fg: colors.textMuted }),
    Text({ content: info.wifi.slice(0, 12), fg: colors.textSecondary }),
    Text({ content: "  │  ", fg: colors.textMuted }),
    Text({ content: `${info.diskFreeGB}GB free`, fg: colors.textSecondary }),
    Text({ content: "  │  ", fg: colors.textMuted }),
    Text({ content: "ctrl+c quit", fg: colors.textDim }),
  ]
}
