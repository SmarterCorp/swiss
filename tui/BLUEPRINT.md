# Blueprint: TUI on bun + @opentui/core

How to build a terminal UI app with bun and @opentui/core correctly from scratch.

---

## 1. Project Setup

```bash
mkdir tui && cd tui
bun init -y
bun add @opentui/core
```

```json
// package.json
{
  "scripts": {
    "start": "bun index.ts"
  }
}
```

## 2. Entry Point

```ts
// index.ts
import { createCliRenderer } from "@opentui/core"
import { createApp } from "./src/app"

const renderer = await createCliRenderer({
  exitOnCtrlC: false,   // handle ctrl+c manually
})

await createApp(renderer)
```

## 3. App Lifecycle — The Golden Rule

Factory functions (`Box()`, `Text()`, `Input()`) return **VNode proxies**, not real Renderables.
All calls before `renderer.root.add()` are queued. All calls after are silently lost.

Follow this exact order:

```ts
// --- Phase 1: Build VNodes, register ALL handlers ---

const input = Input({
  id: "my-input",
  width: "100%",
  placeholder: "Type here...",
  textColor: "#e8e8e8",
  backgroundColor: "#1a1a1a",
  focusedBackgroundColor: "#1a1a1a",
}) as InputRenderable

// Event handlers MUST be registered here, before add()
input.on(InputRenderableEvents.INPUT, (value: string) => {
  // fires on every keystroke
})

input.on(InputRenderableEvents.ENTER, (value: string) => {
  // use findDescendantById inside for post-mount operations
  const real = renderer.root.findDescendantById("my-input") as InputRenderable
  real.value = ""
  // ... handle command ...
  real.focus()
})

// --- Phase 2: Compose the tree ---

const root = Box(
  { flexDirection: "column", width: "100%", height: "100%" },
  // ... children VNodes ...
  input,
  // ...
)

// --- Phase 3: Mount ---

renderer.root.add(root)

// --- Phase 4: Post-mount — only via findDescendantById ---

const realInput = renderer.root.findDescendantById("my-input") as InputRenderable
realInput.focus()
```

## 4. Layout Pattern

Standard REPL layout — header, scrollable content, input, status bar:

```ts
Box(
  { flexDirection: "column", width: "100%", height: "100%" },

  // Header — fixed 1 row
  Box(
    { width: "100%", height: 1, backgroundColor: "#1a1a1a" },
    Text({ content: " App Name", fg: "#d4a574", bold: true }),
  ),

  // Content — fills remaining space, scrollable
  Box(
    { id: "content", flexDirection: "column", width: "100%", flexGrow: 1, overflow: "scroll" },
    ...contentElements,
  ),

  // Input — fixed 1 row (Input is always height 1)
  input,

  // Status bar — fixed 1 row
  Box(
    { width: "100%", height: 1, backgroundColor: "#1a1a1a" },
    Text({ content: " status info", fg: "#888888" }),
  ),
)
```

## 5. Working with Children Post-Mount

After `renderer.root.add()`, manipulate real Renderables through `findDescendantById` and the Renderable API:

```ts
function getContentBox() {
  return renderer.root.findDescendantById("content") as any
}

// Clear and replace content
function replaceContent(elements: any[]) {
  const box = getContentBox()
  if (!box) return
  const children = [...box.getChildren()]    // getChildren(), not .children
  for (const child of children) box.remove(child.id)  // remove() takes string ID
  for (const el of elements) box.add(el)     // add() accepts VNodes here
}

// Append content
function appendContent(elements: any[]) {
  const box = getContentBox()
  if (!box) return
  for (const el of elements) box.add(el)
}
```

## 6. Keyboard Handling

```ts
// Global keyboard — use renderer.keyInput
renderer.keyInput.on("keypress", (key: KeyEvent) => {
  if (key.ctrl && key.name === "c") process.exit(0)
})

// Input-specific — use InputRenderableEvents on VNode (before mount)
input.on(InputRenderableEvents.ENTER, handler)
input.on(InputRenderableEvents.INPUT, handler)
```

## 7. Calling External Commands

```ts
// swiss.ts — CLI bridge with output size limit
const maxOutputBytes = 1024 * 1024

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
    if (total > maxOutputBytes) { reader.cancel(); break }
  }
  return Buffer.concat(chunks).toString("utf-8", 0, Math.min(total, maxOutputBytes))
}

export async function runCommand(args: string[]): Promise<string> {
  const proc = Bun.spawn(args, { stdout: "pipe", stderr: "pipe" })
  const [stdout, stderr] = await Promise.all([
    readLimited(proc.stdout),
    readLimited(proc.stderr),
  ])
  await proc.exited
  return (stdout + stderr).trimEnd()
}
```

## 8. File Structure

```
tui/
  index.ts          — entry point, create renderer
  package.json
  src/
    app.ts          — main app logic, layout, event wiring
    colors.ts       — color palette constants
    welcome.ts      — welcome screen VNode builder
    status-bar.ts   — status bar VNode builder
    system-info.ts  — gather system data at startup
    swiss.ts        — CLI bridge (Bun.spawn wrapper)
    version.ts      — version constant
```

## 9. Build

```bash
# Dev
bun run start

# Compile to single binary
bun build --compile index.ts --outfile ../build/swiss-tui
```

No bundler config needed. Binary is self-contained.

## 10. Cheat Sheet — API Pitfalls

| Trap | Fix |
|------|-----|
| `.on()` / `.focus()` after `add()` — silently lost | Register before `add()`, use `findDescendantById` after |
| `box.remove(child)` — wrong type | `box.remove(child.id)` — takes string |
| `box.children` on mounted box | `box.getChildren()` — returns real Renderables |
| `Input({ height: 1 })` — not in type | Input is always h:1, don't pass it |
| `Input({ focusable: true })` — not an option | Already true by default on EditBufferRenderable |
| `Input({ showCursor: true })` — redundant | Already true by default |
| `as InputRenderable` on VNode | Type lie at runtime — it's still a proxy |
| `input.value = ""` on VNode proxy | Use `realInput.value = ""` via findDescendantById |
