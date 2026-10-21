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
  video.dispatchEvent(new Event("waiting"))
  assert.equal(events.length, 3)
})
