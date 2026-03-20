const maxOutputBytes = 1024 * 1024 // 1 MB

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

  const [stdout, stderr] = await Promise.all([
    readLimited(proc.stdout),
    readLimited(proc.stderr),
  ])

  await proc.exited
  return (stdout + stderr).trimEnd()
}
