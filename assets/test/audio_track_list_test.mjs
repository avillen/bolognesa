import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
const code = await readFile(new URL("../js/music/hooks/audio_player/track_list.js", import.meta.url), "utf8")
const {syncTrackRows} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)

test("streamed row indicators match track and file identity from the shared session", () => {
  const button = {dataset: {playLabel: "Play song", pauseLabel: "Pause song"}, setAttribute(name, value) {this[name] = value}}
  const row = {dataset: {trackId: "3", fileId: "8"}, querySelector: () => button}
  const list = {querySelectorAll: () => [row]}
  const snapshot = {selected: {id: 3, file_id: 8}, paused: false, finished: false}
  syncTrackRows(list, snapshot)
  assert.equal(row.dataset.playback, "playing")
  assert.equal(button["aria-label"], "Pause song")
  assert.equal(button.title, "Pause song")
  snapshot.paused = true
  syncTrackRows(list, snapshot)
  assert.equal(row.dataset.playback, "paused")
  assert.equal(button.title, "Play song")
  snapshot.selected.file_id = 9
  syncTrackRows(list, snapshot)
  assert.equal(row.dataset.playback, "")
})

test("row adapter reconciles stream mutations and disconnects on screen unmount", async () => {
  const {connectTrackRows} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)
  let mutation, disconnected = false, listener
  const button = {dataset: {playLabel: "Play", pauseLabel: "Pause"}, setAttribute() {}}
  const row = {dataset: {trackId: "3", fileId: "8"}, querySelector: () => button}
  const list = {querySelectorAll: () => [row]}
  const snapshot = {selected: {id: 3, file_id: 8}, paused: false}
  const session = {subscribe(fn) {listener = fn; fn(snapshot); return () => {listener = null}}}
  const oldObserver = globalThis.MutationObserver
  globalThis.MutationObserver = class { constructor(fn) {mutation = fn} observe() {} disconnect() {disconnected = true} }
  try {
    const connection = connectTrackRows(list, session)
    snapshot.paused = true; listener(snapshot)
    assert.equal(row.dataset.playback, "paused")
    mutation()
    connection.destroy()
    assert.equal(disconnected, true)
    assert.equal(listener, null)
  } finally { globalThis.MutationObserver = oldObserver }
})
