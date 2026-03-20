import {
  Box, Text, Input,
  InputRenderableEvents,
  type CliRenderer, type KeyEvent, type InputRenderable,
} from "@opentui/core"
import { colors } from "./colors"
import { getSystemInfo } from "./system-info"
import { createWelcomeLines } from "./welcome"
import { createStatusBarTexts } from "./status-bar"
import { runSwissCommand } from "./swiss"
import { version } from "./version"

type Mode = "welcome" | "repl"

export async function createApp(renderer: CliRenderer) {
  let mode: Mode = "welcome"
  let running = false
  let currentInputValue = ""
  const info = await getSystemInfo()

  const welcomeTexts = createWelcomeLines(info)
  const statusTexts = createStatusBarTexts(info)

  // Input() returns a ProxiedVNode — all .on() and method calls before
  // renderer.root.add() are queued as __pendingCalls and replayed during
  // instantiation. Calls AFTER add() go to the dead VNode proxy.
  // So: register ALL event handlers BEFORE add().

  const input = Input({
    id: "cmd-input",
    width: "100%",
    placeholder: "❯ ",
    textColor: colors.textBright,
    backgroundColor: colors.bgSurface,
    focusedBackgroundColor: colors.bgSurface,
  }) as InputRenderable

  input.on(InputRenderableEvents.INPUT, (value: string) => {
    currentInputValue = value
  })

  // ENTER handler must be registered before add() to be replayed during instantiation
  input.on(InputRenderableEvents.ENTER, async (value: string) => {
    const realInput = renderer.root.findDescendantById("cmd-input") as InputRenderable | undefined
    const cmd = value.trim()
    currentInputValue = ""
    if (realInput) realInput.value = ""
    if (!cmd) return

    if (cmd === "quit" || cmd === "exit" || cmd === "q") {
      process.exit(0)
    }

    if (cmd === "clear" || cmd === "home" || cmd === "menu" || cmd === "back" || cmd === "welcome") {
      switchToWelcome()
      if (realInput) realInput.focus()
      return
    }

    await executeCommand(cmd)
    if (realInput) realInput.focus()
  })

  const root = Box(
    { flexDirection: "column", width: "100%", height: "100%", backgroundColor: colors.bg },

    // Header
    Box(
      { width: "100%", height: 1, backgroundColor: colors.bgSurface },
      Text({ content: " swiss", fg: colors.accent, bold: true }),
      Text({ content: ` v${version}`, fg: colors.textDim }),
    ),

    // Content area
    Box(
      { id: "content", flexDirection: "column", width: "100%", flexGrow: 1, overflow: "scroll" },
      ...welcomeTexts,
    ),

    // Input
    input,

    // Status bar
    Box(
      { width: "100%", height: 1, backgroundColor: colors.bgSurface },
      ...statusTexts,
    ),
  )

  renderer.root.add(root)

  // After instantiation, get the real renderable for focus
  const realInput = renderer.root.findDescendantById("cmd-input") as InputRenderable | undefined
  if (realInput) realInput.focus()

  // Content box helpers
  function getContentBox() {
    return renderer.root.findDescendantById("content") as any
  }

  function replaceContent(elements: any[]) {
    const box = getContentBox()
    if (!box) return
    const children = [...box.getChildren()]
    for (const child of children) box.remove(child.id)
    for (const el of elements) box.add(el)
  }

  const maxReplLines = 5000

  function switchToRepl() {
    mode = "repl"
    replaceContent([])
  }

  function switchToWelcome() {
    mode = "welcome"
    replaceContent(createWelcomeLines(info))
  }

  function appendToRepl(lines: Array<{ content: string; fg: string; bold?: boolean }>) {
    const box = getContentBox()
    if (!box) return
    for (const l of lines) {
      box.add(Box({ width: "100%", height: 1 },
        Text({ content: l.content, fg: l.fg, bold: l.bold })
      ))
    }
    const children = box.getChildren()
    if (children.length > maxReplLines) {
      const excess = children.length - maxReplLines
      for (let i = 0; i < excess; i++) {
        box.remove(children[i].id)
      }
    }
  }

  async function executeCommand(cmd: string) {
    if (running) return
    running = true
    try {
      if (mode !== "repl") switchToRepl()
      appendToRepl([{ content: `  ❯ ${cmd}`, fg: colors.accent, bold: true }])
      const output = await runSwissCommand(cmd)
      const outputLines = output.split("\n").map(line => ({
        content: `    ${line || " "}`,
        fg: colors.textNormal,
      }))
      outputLines.push({ content: " ", fg: colors.textDim })
      appendToRepl(outputLines)
    } finally {
      running = false
    }
  }

  // Keyboard — only ctrl+c to exit
  renderer.keyInput.on("keypress", async (key: KeyEvent) => {
    if (key.ctrl && key.name === "c") {
      process.exit(0)
    }
  })
}
