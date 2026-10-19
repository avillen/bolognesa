import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
const code = await readFile(new URL("../js/hooks/audio_track_list.js", import.meta.url), "utf8")
const {syncTrackRows} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)
test("visible rows follow the actual source, playing, paused and ended states", () => {
  const button = {dataset: {playLabel: "Play song", pauseLabel: "Pause song"}, setAttribute(name, value) {this[name] = value}}
  const row = {dataset: {trackSrc: "/song"}, querySelector: () => button}
  const list = {querySelectorAll: () => [row]}
  const audio = {paused: false, ended: false, error: null}
  syncTrackRows(list, audio, "/song")
  assert.equal(row.dataset.playback, "playing")
  assert.equal(button["aria-label"], "Pause song")
  audio.paused = true
  syncTrackRows(list, audio, "/song")
  assert.equal(row.dataset.playback, "paused")
  assert.equal(button["aria-label"], "Play song")
  audio.ended = true
  syncTrackRows(list, audio, "/song")
  assert.equal(row.dataset.playback, "")
  syncTrackRows(list, audio, "/other")
  assert.equal(row.dataset.playback, "")
})

test("row controls toggle the current audio, reconcile streamed rows and clean up", async () => {
  const {connectTrackRows} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)
  const listeners = new Map()
  const button = {dataset: {playLabel: "Play", pauseLabel: "Pause"}, setAttribute() {}, closest: () => row}
  const row = {dataset: {trackSrc: "/song"}, querySelector: () => button}
  let click
  let reconcile
  let disconnected = false
  let plays = 0
  const list = {
    querySelectorAll: () => [row],
    addEventListener: (_event, fn) => {click = fn},
    removeEventListener: () => {click = null},
  }
  const originalObserver = globalThis.MutationObserver
  globalThis.MutationObserver = class {
    constructor(fn) {reconcile = fn}
    observe() {}
    disconnect() {disconnected = true}
  }
  const audio = {
    paused: false, ended: false, error: null,
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
    pause() {this.paused = true; listeners.get("pause")()},
    play() {plays++; this.paused = false; listeners.get("playing")(); return Promise.resolve()},
  }
  const frame = {dataset: {src: "/song", generation: "1"}, closest: () => ({querySelector: () => list})}
  const event = {target: {closest: () => button}, preventDefault() {}, stopImmediatePropagation() {}}
  try {
    const connection = connectTrackRows(frame, audio, () => {})
    click(event)
    assert.equal(row.dataset.playback, "paused")
    click(event)
    assert.equal(plays, 1)
    assert.equal(row.dataset.playback, "playing")
    row.dataset.playback = ""
    reconcile()
    assert.equal(row.dataset.playback, "playing")
    frame.dataset.src = "/other"
    connection.sync()
    assert.equal(row.dataset.playback, "")
    click(event)
    assert.equal(plays, 1)
    connection.destroy()
    assert.equal(disconnected, true)
    assert.equal(listeners.size, 0)
    assert.equal(click, null)
  } finally {
    globalThis.MutationObserver = originalObserver
  }
})
