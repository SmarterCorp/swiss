export interface SystemInfo {
  battery: { percent: number; charging: boolean }
  wifi: string
  diskFreeGB: number
}

export async function getSystemInfo(): Promise<SystemInfo> {
  try {
    const proc = Bun.spawn(["swiss", "dash", "--json"], {
      stdout: "pipe",
      stderr: "pipe",
    })
    const text = await new Response(proc.stdout).text()
    await proc.exited
    const data = JSON.parse(text)

    return {
      battery: {
        percent: data.system?.battery_percent ?? 0,
        charging: data.system?.battery_charging ?? false,
      },
      wifi: data.system?.network_ssid ?? "disconnected",
      diskFreeGB: data.system?.disk_free_bytes
        ? Math.round(data.system.disk_free_bytes / (1024 * 1024 * 1024))
        : 0,
    }
  } catch {
    return { battery: { percent: 0, charging: false }, wifi: "unknown", diskFreeGB: 0 }
  }
}
