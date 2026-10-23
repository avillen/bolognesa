import test from "node:test"
import assert from "node:assert/strict"
import {createPlaybackRecovery} from "../js/playback_recovery.mjs"

function setup(storage = new Map(), data = {}) {
  const video = new EventTarget()
  Object.assign(video, {currentTime: 0, duration: 1000, paused: true, ended: false,
    play() { this.paused = false; this.dispatchEvent(new Event("play")); return Promise.resolve() },
    pause() { this.paused = true; this.dispatchEvent(new Event("pause")) },
  })
  const el = {dataset: {recoveryScope: "1:movie:2", fileId: "3", src: "/media/3", autoplay: "true", ...data}}
  const events = []
  const store = {getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key)}
  const recovery = createPlaybackRecovery({el, video, pushEvent: (...args) => events.push(args)}, store)
  return {video, el, events, recovery, storage}
}

test("reload restores direct playback after metadata and never overwrites progress with startup zero", () => {
  const first = setup()
  first.recovery.source()
  first.recovery.ready()
  first.video.currentTime = 812
  first.video.dispatchEvent(new Event("timeupdate"))
  first.recovery.destroy()
  const next = setup(first.storage)
  next.recovery.source()
  next.video.dispatchEvent(new Event("timeupdate"))
  next.video.dispatchEvent(new Event("pause"))
  assert.equal(next.video.currentTime, 0)
  next.recovery.ready()
  assert.equal(next.video.currentTime, 812)
  assert.equal(next.video.paused, false)
  next.recovery.destroy()
})

test("paused reload stays paused and ended playback clears the saved point", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400
  first.video.pause()
  first.recovery.destroy()
  const next = setup(first.storage)
  next.recovery.source(); next.recovery.ready()
  assert.equal(next.video.currentTime, 400)
  assert.equal(next.video.paused, true)
  next.video.ended = true
  next.video.dispatchEvent(new Event("ended"))
  next.recovery.destroy()
  const replay = setup(first.storage)
  replay.recovery.source(); replay.recovery.ready()
  assert.equal(replay.video.currentTime, 0)
  replay.recovery.destroy()
})

test("HLS recovery requests a global authorized seek once and retains pause across replacement", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400
  first.video.pause(); first.recovery.destroy()
  const next = setup(first.storage, {sessionId: "initial", offsetMs: "0", durationMs: "1000000"})
  assert.equal(next.recovery.source(), false)
  assert.deepEqual(next.events.map(event => event.slice(0, 2)), [["playback_restore", {session_id: "initial", position_ms: "400000", playing: "false"}]])
  next.el.dataset.src = ""
  next.recovery.beforeSourceChange()
  next.recovery.source()
  next.el.dataset.src = "/new-hls"
  next.el.dataset.sessionId = "replacement"
  next.el.dataset.offsetMs = "400000"
  assert.equal(next.recovery.source(), true)
  next.video.fileTimeline = {offset: 400}
  next.recovery.ready()
  assert.equal(next.video.currentTime, 0)
  assert.equal(next.video.paused, true)
  // Later deliberate seeks must not reinstate the restored position.
  next.recovery.beforeSourceChange()
  next.el.dataset.offsetMs = "600000"
  next.recovery.source(); next.recovery.ready()
  assert.equal(next.events.length, 1)
  next.recovery.destroy()
})

test("a rejected HLS restore releases the pending checkpoint and reattaches the source", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400; first.video.pause(); first.recovery.destroy()
  let retry = 0, reply
  const next = setup(first.storage, {sessionId: "stale", offsetMs: "0", durationMs: "1000000"})
  const recovery = createPlaybackRecovery({el: next.el, video: next.video,
    pushEvent: (_name, _payload, callback) => { reply = callback }, retrySource: () => retry++},
    {getItem: key => first.storage.get(key), setItem() {}})
  assert.equal(recovery.source(), false)
  reply({accepted: false})
  assert.equal(retry, 1)
  assert.equal(recovery.source(), true)
  recovery.destroy(); next.recovery.destroy()
})

test("other files and viewers never inherit a checkpoint and unavailable storage is harmless", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 812
  first.video.pause(); first.recovery.destroy()
  for (const data of [{fileId: "9"}, {recoveryScope: "2:movie:2"}]) {
    const next = setup(new Map(first.storage), data)
    next.recovery.source(); next.recovery.ready()
    assert.equal(next.video.currentTime, 0)
    next.recovery.destroy()
  }
  const unavailable = {getItem() { throw Error("blocked") }, setItem() { throw Error("blocked") }, removeItem() { throw Error("blocked") }}
  const {video, el} = setup()
  const recovery = createPlaybackRecovery({video, el, pushEvent() {}}, unavailable)
  recovery.source(); recovery.ready(); recovery.destroy()
})

test("corrupt and expired checkpoints do not block playback or seek beyond the file", () => {
  const key = "bolognesa.playback.checkpoint"
  for (const value of ["broken JSON", JSON.stringify({scope: "1:movie:2", fileId: "3", positionMs: 200,
    paused: true, savedAt: Date.now() - 13 * 60 * 60 * 1000})]) {
    const next = setup(new Map([[key, value]]))
    next.recovery.source(); next.recovery.ready()
    assert.equal(next.video.currentTime, 0)
    assert.equal(next.video.paused, false)
    next.recovery.destroy()
  }
})

test("a rejected direct restore reports the failure and still permits playback", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 812; first.video.pause(); first.recovery.destroy()
  const next = setup(first.storage)
  Object.defineProperty(next.video, "currentTime", {get: () => 0, set() { throw Error("not seekable") }})
  next.recovery.source(); next.recovery.ready()
  // Recovery must not strand the video when seeking fails.
  next.video.paused = false
  next.video.dispatchEvent(new Event("play"))
  next.recovery.destroy()
  assert.equal(JSON.parse(next.storage.get("bolognesa.playback.checkpoint")).positionMs, 0)
})
