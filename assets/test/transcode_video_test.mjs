import test from "node:test"
import assert from "node:assert/strict"
import {createHlsController} from "../js/video/player/controllers/hls.mjs"
const Hls = {isSupported: () => false}

function setup() {
  const events = []
  const el = new EventTarget()
  Object.assign(el, {
    dataset: {transport: "native_hls", sessionId: "a", offsetMs: "120000", durationMs: "600000", autoplay: "false"},
    currentTime: 12.345, paused: false, ended: false,
    canPlayType: () => "probably",
    pause() { this.paused = true; this.dispatchEvent(new Event("pause")) },
  })
  const context = {el, pushEvent: (...args) => events.push(args)}
  context.controller = createHlsController({video: el, config: el.dataset, pushEvent: context.pushEvent, Hls})
  return {context, el, events}
}

test("a committed seek sends file time once and suppresses errors from the obsolete session", () => {
  const {context, el, events} = setup()
  el.fileTimeline.seek(400)
  el.fileTimeline.seek(450)
  context.controller.update(el.dataset)
  el.dispatchEvent(new Event("error"))
  el.dispatchEvent(new Event("pause"))
  assert.deepEqual(events, [["playback_seek", {session_id: "a", position_ms: "400000", playing: "true"}]])
  context.controller.destroy()
})

test("pausing and resuming use the file position and cleanup stops further events", () => {
  const {context, el, events} = setup()
  el.pause()
  el.paused = false
  el.dispatchEvent(new Event("play"))
  assert.deepEqual(events, [
    ["playback_pause", {session_id: "a"}],
    ["playback_resume", {session_id: "a", position_ms: "132345"}],
  ])
  context.controller.destroy()
  assert.equal(el.fileTimeline, undefined)
  el.dispatchEvent(new Event("error"))
  el.dispatchEvent(new Event("ended"))
  assert.equal(events.length, 2)
})

test("current decode errors remain visible while a resume acknowledgement is pending", () => {
  const {context, el, events} = setup()
  el.dataset.attemptId = "attempt"
  el.pause()
  el.paused = false
  el.dispatchEvent(new Event("play"))
  el.error = {code: 3}
  el.dispatchEvent(new Event("error"))
  el.dispatchEvent(new Event("error"))
  assert.deepEqual(events.at(-1), ["transcode_error", {session_id: "a", attempt_id: "attempt",
    error_kind: "media", position_ms: "132345"}])
  assert.equal(events.filter(([event]) => event === "transcode_error").length, 1)
  context.controller.destroy()
})

test("seeking while paused does not request autoplay", () => {
  const {context, el, events} = setup()
  el.paused = true
  el.fileTimeline.seek(20)
  assert.deepEqual(events, [["playback_seek", {session_id: "a", position_ms: "20000", playing: "false"}]])
  context.controller.destroy()
})


test("fatal HLS failures are diagnosed before the session is stopped", () => {
  let hls
  class FakeHls {
    static isSupported() { return true }
    static Events = {MANIFEST_PARSED: "ready", ERROR: "error"}
    constructor(config) { hls = this; this.listeners = {}; this.config = config }
    on(event, listener) { this.listeners[event] = listener }
    loadSource() {} attachMedia() {} destroy() {}
  }
  const calls = []
  const video = new EventTarget()
  Object.assign(video, {dataset: {transport: "hls_js", sessionId: "hls", offsetMs: "0", durationMs: "60000"}})
  const controller = createHlsController({video, config: video.dataset, Hls: FakeHls,
    pushEvent: (...args) => calls.push(args), reportPlaybackError: () => calls.push(["diagnostic"])})
  assert.equal(hls.config.startPosition, 0)
  assert.equal(hls.config.liveSyncDurationCount, 3)
  hls.listeners.error("error", {fatal: true})
  assert.deepEqual(calls, [["diagnostic"], ["transcode_error", {session_id: "hls", attempt_id: undefined,
    error_kind: "unknown", position_ms: "0"}]])
  const lateError = hls.listeners.error
  controller.destroy()
  lateError("error", {fatal: true})
  assert.equal(calls.length, 2)
})

test("native HLS readiness runs once and teardown detaches the ready listener", () => {
  const video = new EventTarget()
  const config = {sessionId: "native", offsetMs: "0", durationMs: "60000", transport: "native_hls", src: "/native.m3u8"}
  Object.assign(video, {canPlayType: () => "probably", dataset: config})
  let ready = 0
  const create = () => createHlsController({video, config, Hls, pushEvent() {}, onReady: () => ready++})
  const controller = create()
  assert.equal(video.src, "/native.m3u8")
  video.dispatchEvent(new Event("loadedmetadata"))
  video.dispatchEvent(new Event("loadedmetadata"))
  assert.equal(ready, 1)
  controller.destroy()
  const replacement = create()
  replacement.destroy()
  video.dispatchEvent(new Event("loadedmetadata"))
  assert.equal(ready, 1)
  assert.equal(video.fileTimeline, undefined)
})

test("an accepted native transport stays native even when HLS.js is available", () => {
  const video = new EventTarget()
  Object.assign(video, {canPlayType: () => "probably"})
  class AvailableHls {
    static isSupported() { return true }
    constructor() { throw Error("must honor selected native transport") }
  }
  const config = {transport: "native_hls", sessionId: "selected", src: "/selected.m3u8", offsetMs: "0"}
  const controller = createHlsController({video, config, Hls: AvailableHls, pushEvent() {}})
  assert.equal(video.src, "/selected.m3u8")
  controller.destroy()
})

for (const [type, kind] of [["mediaError", "media"], ["networkError", "network"], ["otherError", "unknown"]]) {
  test(`fatal ${type} is correlated and emitted once without treating every fatal error as media`, () => {
    let instance
    class FakeHls {
      static isSupported() { return true }
      static Events = {MANIFEST_PARSED: "ready", ERROR: "error"}
      constructor() { instance = this; this.listeners = {} }
      on(name, callback) { this.listeners[name] = callback }
      loadSource() {} attachMedia() {} destroy() {}
    }
    const events = [], video = new EventTarget()
    video.currentTime = 1.5
    const config = {transport: "hls_js", sessionId: "current", attemptId: "attempt", offsetMs: "2000", durationMs: "60000"}
    const controller = createHlsController({video, config, Hls: FakeHls, pushEvent: (...e) => events.push(e)})
    instance.listeners.error("error", {fatal: true, type})
    instance.listeners.error("error", {fatal: true, type})
    assert.deepEqual(events, [["transcode_error", {session_id: "current", attempt_id: "attempt", error_kind: kind, position_ms: "3500"}]])
    controller.destroy()
  })
}

test("autoplay rejection leaves play available without reporting a media failure", async () => {
  const events = [], video = new EventTarget()
  Object.assign(video, {canPlayType: () => "probably", currentTime: 0,
    play: () => Promise.reject(Object.assign(new Error("gesture required"), {name: "NotAllowedError"}))})
  const controller = createHlsController({video, config: {transport: "native_hls", sessionId: "a",
    attemptId: "attempt", autoplay: "true", offsetMs: "0"}, Hls,
    pushEvent: (...e) => events.push(e)})
  video.dispatchEvent(new Event("loadedmetadata"))
  await Promise.resolve()
  assert.deepEqual(events, [])
  controller.destroy()
})
