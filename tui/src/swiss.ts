import type { CliRenderer } from "@opentui/core"

const maxOutputBytes = 1024 * 1024 // 1 MB
const commandTimeoutMs = 30_000 // 30s

// Commands that launch interactive TUI apps — need terminal takeover
export const interactiveCommands = new Set(["rss", "top", "dua", "tui"])

async function readLimited(stream: ReadableStream<Uint8Array> | null): Promise<string> {
  if (!stream) return ""
  const reader = stream.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    chunks.push(value)
    total += value.byteLength
    if (total > maxOutputBytes) {
      reader.cancel()
      break
    }
  }
  const buf = Buffer.concat(chunks)
  return buf.toString("utf-8", 0, Math.min(buf.length, maxOutputBytes))
}

export async function runSwissCommand(input: string): Promise<string> {
  const parts = input.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return ""

  const proc = Bun.spawn(["swiss", ...parts], {
    stdout: "pipe",
    stderr: "pipe",
  })

  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => {
      proc.kill()
      reject(new Error(`Command timed out after ${commandTimeoutMs / 1000}s`))
    }, commandTimeoutMs)
  )

  try {
    const [stdout, stderr] = await Promise.race([
      Promise.all([readLimited(proc.stdout), readLimited(proc.stderr)]),
      timeout,
    ])
    await proc.exited
    return (stdout + stderr).trimEnd()
  } catch (err: any) {
    proc.kill()
    throw err
  }
}

/** Suspend renderer, run interactive command with real terminal, resume */
export async function runInteractiveCommand(input: string, renderer: CliRenderer): Promise<string> {
  const parts = input.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return ""

  renderer.suspend()

  try {
    const proc = Bun.spawn(["swiss", ...parts], {
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    })
    await proc.exited
    return `(${parts[0]} exited)`
  } catch (err: any) {
    return `Error: ${err?.message ?? err}`
  } finally {
    renderer.resume()
  }
}
