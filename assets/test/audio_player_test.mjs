import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
const code = await readFile(new URL("../js/music/hooks/audio_player.js", import.meta.url), "utf8")
const rows = `data:text/javascript;base64,${Buffer.from(await readFile(new URL("../js/music/audio_track_list.js", import.meta.url), "utf8")).toString("base64")}`
const moduleCode = code.replace('"../audio_track_list.js"', JSON.stringify(rows))
const {default: hook} = await import(`data:text/javascript;base64,${Buffer.from(moduleCode).toString("base64")}`)

test("Music screen commands the document session and unmount only detaches it", () => {
  const actions = []
  const listeners = new Map()
  const selected = {id: 3, file_id: 8}
  const session = {
    getSnapshot: () => ({selected, paused: true}),
    subscribe: () => () => {},
    selectTrack: value => actions.push(["select", value]),
    playAlbum: value => actions.push(["album", value]),
    play: () => actions.push(["play"]),
    pause: () => actions.push(["pause"]),
  }
  const list = {querySelectorAll: () => []}
  const button = {dataset: {musicAction: "track", trackId: "3", fileId: "8"}}
  const el = {
    querySelector: () => list,
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
    contains: () => true,
  }
  const originalWindow = globalThis.window
  const originalObserver = globalThis.MutationObserver
  globalThis.MutationObserver = class {constructor() {} observe() {} disconnect() {}}
  globalThis.window = {bolognesaMusicPlayer: {session}}
  const context = {el}
  const event = {target: {closest: () => button}, preventDefault() {}, stopImmediatePropagation() {}}
  try {
    hook.mounted.call(context)
    listeners.get("click")(event)
    assert.deepEqual(actions, [["play"]])
    button.dataset = {musicAction: "track", trackId: "4", fileId: "9"}
    listeners.get("click")(event)
    assert.deepEqual(actions[1], ["select", {trackId: 4, fileId: 9}])
    hook.destroyed.call(context)
    assert.equal(listeners.size, 0)
    assert.ok(context.session === null)
  } finally { globalThis.window = originalWindow; globalThis.MutationObserver = originalObserver }
})
