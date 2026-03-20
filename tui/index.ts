import { createCliRenderer } from "@opentui/core"
import { createApp } from "./src/app"

const renderer = await createCliRenderer({
  exitOnCtrlC: false,
})

await createApp(renderer)
