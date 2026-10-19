import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"

const moduleUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`
const errors = moduleUrl(await readFile(new URL("../js/hooks/audio_error.js", import.meta.url), "utf8"))
const code = (await readFile(new URL("../js/hooks/audio_player.js", import.meta.url), "utf8"))
  .replace('import "../../vendor/videojs.min.mjs"', "")
  .replace('"./audio_error"', JSON.stringify(errors))
const {default: hook} = await import(moduleUrl(code))

test("audio controls preserve refresh state, load new generations once and stop on exit", () => {
  let source = "/first"
  let loads = 0
  let pauses = 0
  let plays = 0
  const listeners = new Map()
  const sourceElement = {
    getAttribute: () => source,
    setAttribute: (_name, value) => { source = value },
    removeAttribute: () => { source = null },
  }
  const audio = {
    dataset: {}, controls: true, currentTime: 3,
    querySelector: () => sourceElement,
    replaceWith() {},
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
    load: () => loads++, pause: () => pauses++,
    play: () => { plays++; return Promise.resolve() },
  }
  const originalDocument = globalThis.document
  globalThis.document = {createElement: () => ({append() {}})}
  const context = {
    el: {querySelector: () => audio, dataset: {src: "/first", generation: "1", playRequested: "false", stopped: "false"}},
    pushEvent() {},
  }
  try {
    hook.mounted.call(context)
    assert.equal(audio.controls, false)
    hook.updated.call(context)
    assert.equal(loads, 0)
    assert.equal(audio.currentTime, 3)
    Object.assign(context.el.dataset, {src: "/second", generation: "2", playRequested: "true"})
    hook.updated.call(context)
    hook.updated.call(context)
    assert.equal(source, "/second")
    assert.equal(loads, 1)
    assert.equal(plays, 1)
    assert.equal(audio.dataset.generation, "2")
    hook.destroyed.call(context)
    assert.equal(listeners.size, 0)
    assert.equal(pauses, 1)
    assert.equal(loads, 2)
    assert.equal(source, null)
  } finally {
    globalThis.document = originalDocument
  }
})
