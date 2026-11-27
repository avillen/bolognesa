import test from "node:test"
import assert from "node:assert/strict"
import {createPlaybackRecovery} from "../js/video/player/playback_recovery.mjs"

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

test("the checkpoint becomes the start hint and HLS attaches once at the server offset", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400
  first.video.pause(); first.recovery.destroy()
  const next = setup(first.storage)
  assert.deepEqual(next.recovery.initial(), {position_ms: 400000, paused: true})
  Object.assign(next.el.dataset, {sessionId: "initial", offsetMs: "400000", durationMs: "1000000", autoplay: "false"})
  assert.equal(next.recovery.source(), true)
  next.video.fileTimeline = {offset: 400}
  next.recovery.ready()
  assert.equal(next.video.currentTime, 0)
  assert.equal(next.video.paused, true)
  // Later deliberate seeks must not reinstate the restored position.
  next.recovery.beforeSourceChange()
  next.el.dataset.offsetMs = "600000"
  assert.equal(next.recovery.source(), true)
  next.recovery.ready()
  assert.deepEqual(next.events, [])
  next.recovery.destroy()
})

test("a refused hint plays the server offset with its default intent and no restore request", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400; first.video.pause(); first.recovery.destroy()
  const reports = []
  const next = setup(first.storage, {sessionId: "zero", offsetMs: "0", durationMs: "1000000", autoplay: "true"})
  const recovery = createPlaybackRecovery({el: next.el, video: next.video, pushEvent: (...args) => next.events.push(args),
    diagnostics: {report: kind => reports.push(kind)}}, {getItem: key => first.storage.get(key), setItem() {}})
  assert.equal(recovery.source(), true)
  recovery.ready()
  assert.deepEqual(reports, ["restore_failed"])
  assert.deepEqual(next.events, [])
  assert.equal(next.video.paused, false)
  recovery.destroy(); next.recovery.destroy()
})

test("rejected autoplay of a restored stream leaves controls usable", async () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400; first.recovery.destroy()
  const reports = []
  const next = setup(first.storage, {sessionId: "initial", offsetMs: "400000", durationMs: "1000000"})
  next.video.play = () => Promise.reject(new Error("NotAllowedError"))
  const recovery = createPlaybackRecovery({el: next.el, video: next.video, pushEvent() {},
    diagnostics: {report: kind => reports.push(kind)}}, {getItem: key => first.storage.get(key), setItem() {}})
  assert.equal(recovery.source(), true)
  recovery.ready()
  await new Promise(setImmediate)
  assert.deepEqual(reports, ["restored", "autoplay_blocked"])
  recovery.destroy(); next.recovery.destroy()
})

test("no, corrupt or foreign checkpoints send no start hint", () => {
  const key = "bolognesa.playback.checkpoint"
  assert.equal(setup().recovery.initial(), null)
  const foreign = JSON.stringify({scope: "1:movie:2", fileId: "9", positionMs: 200, paused: true, savedAt: Date.now()})
  for (const value of ["broken JSON", foreign]) assert.equal(setup(new Map([[key, value]])).recovery.initial(), null)
  const blocked = setup()
  const recovery = createPlaybackRecovery({el: blocked.el, video: blocked.video, pushEvent() {}}, {getItem() { throw Error("blocked") }})
  assert.equal(recovery.initial(), null)
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

test("switching episodes saves outgoing progress under the outgoing content scope", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 812
  first.el.dataset.recoveryScope = "1:episode:99"
  first.recovery.beforeSourceChange()
  assert.equal(JSON.parse(first.storage.get("bolognesa.playback.checkpoint")).scope, "1:movie:2")
  first.video.currentTime = 0
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 10
  first.video.pause()
  assert.equal(JSON.parse(first.storage.get("bolognesa.playback.checkpoint")).scope, "1:episode:99")
  first.recovery.destroy()
})

test("same-file retry restores the checkpoint without remounting the player", () => {
  for (const delivery of ["direct", "hls"]) {
    const first = setup()
    first.recovery.source(); first.recovery.ready()
    first.video.currentTime = 400
    first.recovery.beforeSourceChange()
    first.video.currentTime = 0
    first.recovery.beforeSourceChange()
    // The retried attempt renegotiates with the checkpoint as its hint, so HLS starts there.
    if (delivery === "hls") Object.assign(first.el.dataset, {sessionId: "retry", offsetMs: "400000"})
    assert.equal(first.recovery.source({retry: true}), true)
    if (delivery === "hls") first.video.fileTimeline = {offset: 400}
    first.recovery.ready()
    assert.equal((first.video.fileTimeline?.offset || 0) + first.video.currentTime, 400)
    assert.equal(first.video.paused, false)
    first.recovery.destroy()
  }
})

test("checking suspends checkpoints so clearing the element cannot save startup zero", () => {
  const first = setup()
  first.recovery.source(); first.recovery.ready()
  first.video.currentTime = 400
  first.video.pause()
  first.recovery.suspend()
  first.video.currentTime = 0
  first.video.dispatchEvent(new Event("pause"))
  first.recovery.beforeSourceChange()
  first.recovery.destroy()
  const next = setup(first.storage)
  next.recovery.source(); next.recovery.ready()
  assert.equal(next.video.currentTime, 400)
  next.recovery.destroy()
})
