import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
const source = (await readFile(new URL("../js/hooks/compatible_video.js", import.meta.url), "utf8"))
  .replace('import Hls from "../../vendor/hls.min.mjs"', 'const Hls = {isSupported: () => false}')
const {default: hook} = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

function setup() {
  const events = []
  const el = new EventTarget()
  Object.assign(el, {
    dataset: {sessionId: "a", offsetMs: "120000", durationMs: "600000", autoplay: "false"},
    currentTime: 12.345, paused: false, ended: false,
    canPlayType: () => "probably",
    pause() { this.paused = true; this.dispatchEvent(new Event("pause")) },
  })
  const context = {el, pushEvent: (...args) => events.push(args)}
  hook.mounted.call(context)
  return {context, el, events}
}

test("a committed seek sends file time once and suppresses errors from the obsolete session", () => {
  const {context, el, events} = setup()
  el.fileTimeline.seek(400)
  el.fileTimeline.seek(450)
  hook.updated.call(context)
  el.dispatchEvent(new Event("error"))
  el.dispatchEvent(new Event("pause"))
  assert.deepEqual(events, [["playback_seek", {session_id: "a", position_ms: "400000", playing: "true"}]])
  hook.destroyed.call(context)
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
  hook.destroyed.call(context)
  assert.equal(el.fileTimeline, undefined)
  el.dispatchEvent(new Event("error"))
  el.dispatchEvent(new Event("ended"))
  assert.equal(events.length, 2)
})

test("seeking while paused does not request autoplay", () => {
  const {context, el, events} = setup()
  el.paused = true
  el.fileTimeline.seek(20)
  assert.deepEqual(events, [["playback_seek", {session_id: "a", position_ms: "20000", playing: "false"}]])
  hook.destroyed.call(context)
})
