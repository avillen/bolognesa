import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
const code = await readFile(new URL("../js/hooks/video_error.js", import.meta.url), "utf8")
const {default: hook} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)

test("reports the failed position once and removes its listener", () => {
  const events = []
  const listeners = new Map()
  const context = {
    el: {dataset: {fileId: "7"}, currentTime: 12.345, error: null,
      addEventListener: (name, fn) => listeners.set(name, fn),
      removeEventListener: name => listeners.delete(name)},
    pushEvent: (...args) => events.push(args),
  }
  hook.mounted.call(context)
  listeners.get("error")()
  listeners.get("error")()
  assert.deepEqual(events, [["playback_error", {file_id: "7", position_ms: "12345"}]])
  hook.destroyed.call(context)
  assert.equal(listeners.size, 0)
})

test("handles an error already present when mounted and an unknown position", () => {
  const events = []
  const context = {
    el: {dataset: {fileId: "8"}, currentTime: NaN, error: {code: 4},
      addEventListener() {}, removeEventListener() {}},
    pushEvent: (...args) => events.push(args),
  }
  hook.mounted.call(context)
  assert.deepEqual(events, [["playback_error", {file_id: "8", position_ms: "0"}]])
})

test("reports completion with the current file and cleans up", () => {
  const events = []
  const listeners = new Map()
  const context = {
    el: {dataset: {fileId: "9"}, error: null,
      addEventListener: (name, fn) => listeners.set(name, fn),
      removeEventListener: name => listeners.delete(name)},
    pushEvent: (...args) => events.push(args),
  }
  hook.mounted.call(context)
  listeners.get("ended")()
  assert.deepEqual(events, [["playback_ended", {file_id: "9"}]])
  hook.destroyed.call(context)
  assert.equal(listeners.size, 0)
})
