import test from "node:test"
import assert from "node:assert/strict"
import hook from "../js/music/hooks/audio_player.js"

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

test("add-to-queue action reports the result", async () => {
  const listeners = new Map()
  const feedback = {dataset: {added: "Added to queue", failed: "Could not add"}, textContent: ""}
  const calls = []
  const session = {subscribe: () => () => {}, appendTrack: async value => { calls.push(value); return true }}
  const list = {querySelectorAll: () => []}
  const button = {dataset: {musicAction: "append-track", trackId: "4", fileId: "9"}}
  const el = {querySelector: selector => selector === "#music-queue-feedback" ? feedback : list, addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name), contains: () => true}
  const originalWindow = globalThis.window
  const originalObserver = globalThis.MutationObserver
  globalThis.MutationObserver = class {observe() {} disconnect() {}}
  globalThis.window = {bolognesaMusicPlayer: {session}}
  const context = {el}
  try {
    hook.mounted.call(context)
    listeners.get("click")({target: {closest: () => button}, preventDefault() {}, stopImmediatePropagation() {}})
    await new Promise(resolve => setImmediate(resolve))
    assert.deepEqual(calls, [{trackId: 4, fileId: 9}])
    assert.equal(feedback.textContent, "Added to queue")
    assert.equal(feedback.dataset.visible, "true")
    hook.destroyed.call(context)
  } finally { globalThis.window = originalWindow; globalThis.MutationObserver = originalObserver }
})

test("a playback action closes a different open track menu", () => {
  const listeners = new Map()
  const menu = {open: true}
  const button = {dataset: {musicAction: "track", trackId: "1", fileId: "2"}, closest: () => null}
  const session = {subscribe: () => () => {}, getSnapshot: () => ({selected: null}), selectTrack() {}}
  const list = {querySelectorAll: () => []}
  const el = {querySelector: () => list, querySelectorAll: () => [menu], contains: () => true, addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener() {}}
  const originalWindow = globalThis.window, originalObserver = globalThis.MutationObserver
  globalThis.window = {bolognesaMusicPlayer: {session}}
  globalThis.MutationObserver = class {observe() {} disconnect() {}}
  try {
    const context = {el}
    hook.mounted.call(context)
    listeners.get("click")({target: {closest: () => button}, preventDefault() {}, stopImmediatePropagation() {}})
    assert.equal(menu.open, false)
    hook.destroyed.call(context)
  } finally { globalThis.window = originalWindow; globalThis.MutationObserver = originalObserver }
})

test("refreshes visible track dates after listening activity is saved", () => {
  const listeners = []
  const session = {subscribe(fn) { listeners.push(fn); fn({activityRevision: 0}); return () => {} }}
  const list = {querySelectorAll: () => []}
  const el = {querySelector: () => list, addEventListener() {}, removeEventListener() {}}
  const originalWindow = globalThis.window, originalObserver = globalThis.MutationObserver
  globalThis.window = {bolognesaMusicPlayer: {session}}
  globalThis.MutationObserver = class {observe() {} disconnect() {}}
  const events = []
  try {
    const context = {el, pushEvent: (...args) => events.push(args)}
    hook.mounted.call(context)
    for (const listener of listeners) listener({activityRevision: 1, activityTrackId: 3})
    assert.deepEqual(events, [["listening-activity", {track_id: 3}]])
    hook.destroyed.call(context)
  } finally { globalThis.window = originalWindow; globalThis.MutationObserver = originalObserver }
})
