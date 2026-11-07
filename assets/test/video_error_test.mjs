import test from "node:test"
import assert from "node:assert/strict"
import {createDirectController} from "../js/video/player/controllers/direct.mjs"
const mount = context => {
  context.controller = createDirectController({video: context.el, config: context.el.dataset, pushEvent: context.pushEvent})
}

test("reports the failed position once and removes its listener", () => {
  const events = []
  const listeners = new Map()
  const context = {
    el: {dataset: {fileId: "7", attemptId: "attempt"}, currentTime: 12.345, error: {code: 3},
      addEventListener: (name, fn) => listeners.set(name, fn),
      removeEventListener: name => listeners.delete(name)},
    pushEvent: (...args) => events.push(args),
  }
  mount(context)
  listeners.get("error")()
  listeners.get("error")()
  assert.deepEqual(events, [["playback_error", {file_id: "7", attempt_id: "attempt", error_kind: "media", position_ms: "12345"}]])
  context.controller.destroy()
  assert.equal(listeners.size, 0)
})

test("handles an error already present when mounted and an unknown position", () => {
  const events = []
  const context = {
    el: {dataset: {fileId: "8", attemptId: "second"}, currentTime: NaN, error: {code: 4},
      addEventListener() {}, removeEventListener() {}},
    pushEvent: (...args) => events.push(args),
  }
  mount(context)
  assert.deepEqual(events, [["playback_error", {file_id: "8", attempt_id: "second", error_kind: "unknown", position_ms: "0"}]])
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
  mount(context)
  listeners.get("ended")()
  assert.deepEqual(events, [["playback_ended", {file_id: "9"}]])
  context.controller.destroy()
  assert.equal(listeners.size, 0)
})

for (const [code, kind] of [[1, "aborted"], [2, "network"], [3, "media"], [4, "unknown"], [0, "unknown"]]) {
  test(`classifies media element error ${code} without promoting it to decode failure`, () => {
    const events = []
    createDirectController({video: {error: {code}, currentTime: 0,
      addEventListener() {}, removeEventListener() {}},
      config: {fileId: "9", attemptId: "current"}, pushEvent: (...event) => events.push(event)})
    assert.equal(events[0][1].error_kind, kind)
  })
}
