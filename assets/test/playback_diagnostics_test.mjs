import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"

const source = await readFile(new URL("../js/playback_diagnostics.mjs", import.meta.url), "utf8")
const {createPlaybackDiagnostics} = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

function setup(createDiagnostics = createPlaybackDiagnostics) {
  const events = []
  const doc = new EventTarget()
  doc.visibilityState = "visible"
  const video = new EventTarget()
  Object.assign(video, {currentTime: 12, paused: false, error: null, fileTimeline: {offset: 120}})
  const el = {dataset: {fileId: "3", sessionId: "session"}}
  const diagnostics = createDiagnostics({el, video, pushEvent: (...args) => events.push(args)}, doc)
  return {events, doc, video, diagnostics}
}

test("diagnostics preserve file time and buffer a bounded disconnect history until reconnect", () => {
  const {events, doc, diagnostics} = setup()
  assert.equal(events[0][0], "playback_diagnostic")
  assert.equal(events[0][1].diagnostic, "mounted")
  assert.equal(events[0][1].position_ms, 132000)
  diagnostics.disconnected()
  for (let i = 0; i < 20; i++) doc.dispatchEvent(new Event("visibilitychange"))
  assert.equal(events.length, 1)
  diagnostics.reconnected()
  assert.equal(events.length, 10) // initial + up to 8 pending + reconnect
  assert.equal(events.at(-1)[1].diagnostic, "reconnected")
  assert.equal(new Set(events.map(([, data]) => data.tab_id)).size, 1)
  diagnostics.destroy()
})

test("error diagnostics are bounded and cleanup removes listeners", () => {
  const {events, doc, video, diagnostics} = setup()
  video.error = {code: 4, message: "private error"}
  video.dispatchEvent(new Event("error"))
  assert.equal(events.at(-1)[1].media_error, 4)
  assert.equal(JSON.stringify(events).includes("private"), false)
  diagnostics.destroy()
  const count = events.length
  doc.dispatchEvent(new Event("visibilitychange"))
  video.dispatchEvent(new Event("error"))
  assert.equal(events.length, count)
})


test("diagnostics work on HTTP LAN origins without randomUUID or session storage", async () => {
  const previousCrypto = Object.getOwnPropertyDescriptor(globalThis, "crypto")
  const previousStorage = Object.getOwnPropertyDescriptor(globalThis, "sessionStorage")
  Object.defineProperty(globalThis, "crypto", {value: undefined, configurable: true})
  Object.defineProperty(globalThis, "sessionStorage", {get() { throw new Error("storage disabled") }, configurable: true})
  try {
    const fresh = await import(`data:text/javascript;base64,${Buffer.from(source + "\n// HTTP fallback").toString("base64")}`)
    const {events, diagnostics} = setup(fresh.createPlaybackDiagnostics)
    assert.match(events[0][1].tab_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
    diagnostics.disconnected()
    diagnostics.reconnected()
    assert.equal(events.length, 3)
    diagnostics.destroy()
  } finally {
    if (previousCrypto) Object.defineProperty(globalThis, "crypto", previousCrypto)
    else delete globalThis.crypto
    if (previousStorage) Object.defineProperty(globalThis, "sessionStorage", previousStorage)
    else delete globalThis.sessionStorage
  }
})


test("waiting reports buffer and one measured recovery without duplicate stalls", t => {
  let clock = 1000
  t.mock.method(performance, "now", () => clock)
  const {events, video, diagnostics} = setup()
  video.buffered = {length: 1, start: () => 10, end: () => 15}
  video.dispatchEvent(new Event("waiting"))
  video.dispatchEvent(new Event("waiting"))
  assert.equal(events.length, 2)
  assert.equal(events.at(-1)[1].diagnostic, "waiting")
  assert.equal(events.at(-1)[1].buffered_ms, 3000)
  clock = 2600
  video.dispatchEvent(new Event("playing"))
  assert.equal(events.at(-1)[1].diagnostic, "recovered")
  assert.equal(events.at(-1)[1].stall_duration_ms, 1600)
  video.dispatchEvent(new Event("playing"))
  assert.equal(events.length, 3)
  video.paused = true
  video.dispatchEvent(new Event("waiting"))
  assert.equal(events.length, 3)
  diagnostics.destroy()
  video.paused = false
  const afterDestroy = events.length
  video.dispatchEvent(new Event("waiting"))
  assert.equal(events.length, afterDestroy)
})

test("page lifecycle and socket closure retain bounded evidence for the next page", () => {
  const stored = new Map()
  const storage = {getItem: k => stored.get(k), setItem: (k, v) => stored.set(k, v), removeItem: k => stored.delete(k)}
  const win = new EventTarget()
  win.navigator = {onLine: true}
  win.performance = {getEntriesByType: () => [{type: "reload"}]}
  const events = []
  const video = new EventTarget()
  Object.assign(video, {currentTime: 812, paused: false, readyState: 4, networkState: 2})
  const el = {dataset: {fileId: "3", recoveryScope: "1:movie:2"}}
  const doc = new EventTarget()
  doc.visibilityState = "visible"
  const hook = {el, video, recovery: {save() {}}, pushEvent: (name, payload) => events.push(payload)}
  const first = createPlaybackDiagnostics(hook, doc, win, storage)
  const close = new Event("bolognesa:transport")
  close.detail = {diagnostic: "socket_closed", ws_code: 1006, ws_clean: false, reason: "private text"}
  win.dispatchEvent(close)
  win.dispatchEvent(new Event("pagehide"))
  assert.equal(events.at(-1).diagnostic, "pagehide")
  assert.equal(events.at(-1).navigation_type, "reload")
  const socket = events.find(x => x.diagnostic === "socket_closed")
  assert.equal(socket.ws_code, 1006)
  assert.equal(socket.ws_clean, false)
  assert.equal(JSON.stringify(events).includes("private text"), false)
  first.destroy()
  events.length = 0
  const second = createPlaybackDiagnostics(hook, doc, win, storage)
  assert.ok(events.some(x => x.replayed && x.diagnostic === "socket_closed" && x.position_ms === 812000))
  assert.match(events.at(-1).page_id, /^[0-9a-f-]{36}$/)
  second.destroy()
})

test("progress samples retain position without producing events on every time update", () => {
  const {events, video, diagnostics} = setup()
  for (let i = 0; i < 100; i++) video.dispatchEvent(new Event("timeupdate"))
  assert.equal(events.length, 1)
  diagnostics.report("progress")
  assert.equal(events.at(-1)[1].diagnostic, "progress")
  assert.equal(events.at(-1)[1].ready_state, 0)
  diagnostics.destroy()
})

test("acknowledgements from a destroyed hook cannot overwrite the replacement history", () => {
  const stored = new Map()
  const storage = {getItem: k => stored.get(k), setItem: (k, v) => stored.set(k, v)}
  const doc = new EventTarget()
  doc.visibilityState = "visible"
  const video = new EventTarget()
  Object.assign(video, {currentTime: 12, paused: false})
  const el = {dataset: {fileId: "3", recoveryScope: "1:movie:2"}}
  const acks = []
  const hook = {el, video, pushEvent: (_name, _payload, ack) => acks.push(ack)}
  const first = createPlaybackDiagnostics(hook, doc, undefined, storage)
  first.destroy()
  const second = createPlaybackDiagnostics(hook, doc, undefined, storage)
  second.report("socket_closed")
  const before = stored.get("bolognesa.playback.diagnostics")
  acks[0]()
  assert.equal(stored.get("bolognesa.playback.diagnostics"), before)
  acks.at(-1)()
  assert.equal(JSON.parse(stored.get("bolognesa.playback.diagnostics")).events.some(x => x.diagnostic === "socket_closed"), false)
  second.destroy()
})

test("the periodic progress timer stops when the hook is destroyed", t => {
  t.mock.timers.enable({apis: ["setInterval"]})
  const {events, diagnostics} = setup()
  t.mock.timers.tick(30000)
  assert.equal(events.at(-1)[1].diagnostic, "progress")
  diagnostics.destroy()
  const count = events.length
  t.mock.timers.tick(60000)
  assert.equal(events.length, count)
})
