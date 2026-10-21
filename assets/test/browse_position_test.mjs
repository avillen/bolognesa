import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"

const code = await readFile(new URL("../js/hooks/browse_position.js", import.meta.url), "utf8")
const {default: hook} = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`)

test("browse positions wait for asynchronous results and save under the outgoing page", () => {
  const previous = Object.fromEntries(["window", "sessionStorage", "requestAnimationFrame", "cancelAnimationFrame"].map(key => [key, globalThis[key]]))
  const listeners = new Map()
  let rows = JSON.stringify([["/series?page=2", 440]])
  let frame
  const el = {
    dataset: {loading: "true"},
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name),
  }
  const instance = {el}
  globalThis.window = {
    location: {pathname: "/series", search: "?query=&page=2"}, scrollY: 0,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name),
    scrollTo: (_x, y) => { window.scrollY = y },
  }
  globalThis.sessionStorage = {getItem: () => rows, setItem: (_key, value) => { rows = value }}
  globalThis.requestAnimationFrame = callback => { frame = callback; return 1 }
  globalThis.cancelAnimationFrame = () => { frame = null }
  try {
    hook.mounted.call(instance)
    assert.equal(frame, undefined)
    el.dataset.loading = "false"
    hook.updated.call(instance)
    frame()
    assert.equal(window.scrollY, 440)
    window.scrollY = 550
    listeners.get("click")({target: {closest: () => ({})}})
    assert.deepEqual(JSON.parse(rows), [["/series?page=2", 550]])
    window.location.search = "?page=3"
    el.dataset.loading = "true"
    hook.updated.call(instance)
    listeners.get("phx:page-loading-start")()
    assert.deepEqual(JSON.parse(rows), [["/series?page=2", 550]])
    hook.destroyed.call(instance)
    assert.equal(listeners.size, 0)
  } finally {
    Object.assign(globalThis, previous)
  }
})

test("browsing still works when per-tab storage is blocked", () => {
  const previous = Object.fromEntries(["window", "sessionStorage", "requestAnimationFrame", "cancelAnimationFrame"].map(key => [key, globalThis[key]]))
  globalThis.window = {location: {pathname: "/series", search: ""}, scrollY: 0, scrollTo() {}, addEventListener() {}, removeEventListener() {}}
  globalThis.sessionStorage = {getItem() {throw new Error("blocked")}, setItem() {throw new Error("blocked")}}
  globalThis.requestAnimationFrame = callback => {callback(); return 1}
  globalThis.cancelAnimationFrame = () => {}
  const instance = {el: {dataset: {loading: "false"}, addEventListener() {}, removeEventListener() {}}}
  try {
    hook.mounted.call(instance)
    instance.save()
    hook.destroyed.call(instance)
  } finally {
    Object.assign(globalThis, previous)
  }
})
