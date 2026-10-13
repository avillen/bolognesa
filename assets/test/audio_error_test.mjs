import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
const code = await readFile(new URL("../js/hooks/audio_error.js", import.meta.url), "utf8")
const {default: hook} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)
test("refresh preserves audio and selecting a different source loads exactly once", () => {
  let source = "/first"
  let loads = 0
  const listeners = []
  const context = {el: {querySelector: () => ({getAttribute: () => source}), addEventListener: (...args) => listeners.push(args), removeEventListener: (...args) => listeners.splice(listeners.findIndex(item => item[0] === args[0] && item[1] === args[1] && item[2] === args[2]), 1), load: () => loads++}, pushEvent() {}}
  hook.mounted.call(context)
  hook.updated.call(context)
  assert.equal(loads, 0)
  source = "/second"
  hook.updated.call(context)
  hook.updated.call(context)
  assert.equal(loads, 1)
  hook.destroyed.call(context)
  assert.equal(listeners.length, 0)
})
