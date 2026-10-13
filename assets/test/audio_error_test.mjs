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

test("album playback starts, advances on ended and reports blocked autoplay", async () => {
  const events = []
  const listeners = new Map()
  const context = {el: {dataset: {generation: "1", playRequested: "true", stopped: "false"}, querySelector: () => ({getAttribute: () => "/first"}), addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name), play: () => Promise.reject(Object.assign(new Error(), {name: "NotAllowedError"})), pause() {}, load() {}}, pushEvent: (...args) => events.push(args)}
  hook.mounted.call(context)
  await new Promise(resolve => setImmediate(resolve))
  assert.deepEqual(events, [["audio-blocked", {generation: "1"}]])
  listeners.get("ended")()
  assert.deepEqual(events[1], ["audio-ended", {generation: "1"}])
  hook.destroyed.call(context)
  assert.equal(listeners.size, 0)
})

test("a stale play rejection cannot replace feedback for a newer song or a destroyed player", async () => {
  let rejectPlay
  const events = []
  const context = {el: {dataset: {generation: "1", playRequested: "true", stopped: "false"}, querySelector: () => ({getAttribute: () => "/same"}), addEventListener() {}, removeEventListener() {}, play: () => new Promise((_resolve, reject) => { rejectPlay = reject }), pause() {}, load() {}}, pushEvent: (...args) => events.push(args)}
  hook.mounted.call(context)
  const rejectFirst = rejectPlay
  context.el.dataset.generation = "2"
  hook.updated.call(context)
  rejectFirst(Object.assign(new Error(), {name: "NotAllowedError"}))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(events.length, 0)
  hook.destroyed.call(context)
  rejectPlay(Object.assign(new Error(), {name: "NotSupportedError"}))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(events.length, 0)
})
