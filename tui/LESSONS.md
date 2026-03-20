# TUI lessons learned

## Hard-won lessons from building swiss TUI with bun + @opentui/core — VNode lifecycle, API gotchas, architecture decisions

---

# TUI Retrospective: bun + @opentui/core

## Critical: VNode Proxy Lifecycle

The single most important thing to understand about @opentui/core.

**Factory functions (`Box()`, `Text()`, `Input()`) return ProxiedVNode, NOT real Renderables.**

The proxy queues all method calls (`.on()`, `.focus()`, `.value = x`) as `__pendingCalls`. These are replayed **once** during `instantiate()`, which happens inside `renderer.root.add(root)`. After that, the VNode proxy is dead — calls on it silently queue and are never executed.

**Why:** The VNode is a virtual description; the real Renderable is created lazily when the tree is mounted. The proxy exists for a builder-style API (`Input({...}).on(...).on(...)`) but has no link back to the instantiated renderable.

**How to apply:**

1. Register ALL event handlers (`.on()`) on VNodes BEFORE `renderer.root.add()`
2. After `add()`, use `renderer.root.findDescendantById("id")` to get the real Renderable
3. All post-mount operations (focus, value changes, dynamic styling) must go through the real Renderable
4. The `as InputRenderable` cast on a VNode is a type lie — it's still a proxy at runtime

```ts
// WRONG — .on() after add() is silently lost
renderer.root.add(root)
input.on(InputRenderableEvents.ENTER, handler)  // dead proxy

// RIGHT — register before add, use findDescendantById after
input.on(InputRenderableEvents.ENTER, handler)
renderer.root.add(root)
const realInput = renderer.root.findDescendantById("cmd-input") as InputRenderable
realInput.focus()
```

## API Surface Notes

### Renderable.remove() takes a string ID, not a Renderable
```ts
// WRONG
box.remove(child)
// RIGHT
box.remove(child.id)
```

### Renderable.getChildren() returns real Renderables
After mount, use `box.getChildren()` — not `.children` (which is the VNode's children array).

### InputRenderableOptions excludes height
`InputRenderableOptions` extends `Omit<TextareaOptions, "height" | "minHeight" | "maxHeight" | ...>`. Input is always height 1. Don't pass `height: 1` — it's not in the type (TypeScript won't catch it due to `as` cast).

### showCursor defaults to true
`EditBufferRenderable._defaultOptions.showCursor = true`. No need to set explicitly.

### focusable is not an option
`_focusable` is a protected property on Renderable, not a constructor option. `EditBufferRenderable` sets it to true by default.

### createCliRenderer returns a Promise
```ts
const renderer = await createCliRenderer({ exitOnCtrlC: false })
```

### renderer.keyInput for global keyboard events
```ts
renderer.keyInput.on("keypress", (key: KeyEvent) => { ... })
```

## Build & Compile

- `bun run start` — dev mode (`bun index.ts`)
- `bun build --compile index.ts --outfile ../build/swiss-tui` — single binary
- No bundler config needed, bun handles everything
- Binary is self-contained, no node_modules at runtime

## Architecture Decisions

- **One file per concern**: app.ts (main), colors.ts, welcome.ts, status-bar.ts, system-info.ts, swiss.ts (CLI bridge), logic.ts (pure functions), version.ts
- **CLI bridge**: TUI calls `swiss` CLI binary via `Bun.spawn`, reads stdout+stderr with size limit (1MB)
- **System info**: fetched once at startup via `swiss dash --json`
- **Layout**: flexbox column — header (h:1), content (flexGrow:1, scroll), input, status bar (h:1)
- **Content swap**: `replaceContent()` clears children by ID and re-adds — used for welcome/repl mode switch
- **logic.ts**: pure functions extracted for potential testability, but currently unused by app.ts (app.ts has inline equivalents)
