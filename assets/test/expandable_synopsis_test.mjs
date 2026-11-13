import test from "node:test"
import assert from "node:assert/strict"
import hook from "../js/shared/hooks/expandable_synopsis.js"

test("synopsis expansion follows actual overflow, resizing and LiveView updates", () => {
  const previous = {ResizeObserver: globalThis.ResizeObserver, getComputedStyle: globalThis.getComputedStyle}
  let resize
  let disconnected = false
  const text = {scrollHeight: 40, clientHeight: 40}
  const attributes = new Map()
  const listeners = new Map()
  const summary = {
    setAttribute: (name, value) => attributes.set(name, value),
    removeAttribute: name => attributes.delete(name),
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name),
  }
  const el = {
    open: false,
    dataset: {},
    querySelector: selector => selector === "summary" ? summary : text,
  }
  globalThis.getComputedStyle = () => ({lineHeight: "20"})
  globalThis.ResizeObserver = class {
    constructor(callback) { resize = callback }
    observe() {}
    disconnect() { disconnected = true }
  }
  const instance = {el}
  let prevented = false
  try {
    hook.mounted.call(instance)
    assert.equal(el.dataset.expandable, "false")
    assert.equal(attributes.get("tabindex"), "-1")
    listeners.get("click")({preventDefault() { prevented = true }})
    assert.equal(prevented, true)

    text.scrollHeight = 120
    text.clientHeight = 60
    resize()
    assert.equal(el.dataset.expandable, "true")
    assert.equal(attributes.has("tabindex"), false)
    prevented = false
    listeners.get("click")({preventDefault() { prevented = true }})
    assert.equal(prevented, false)

    el.open = true
    text.clientHeight = 120
    resize()
    assert.equal(el.dataset.expandable, "true", "expanded text still offers collapse")

    text.scrollHeight = 40
    text.clientHeight = 40
    hook.updated.call(instance)
    assert.equal(el.dataset.expandable, "false", "short replacement text needs no expansion")
    assert.equal(el.open, false)

    hook.destroyed.call(instance)
    assert.equal(disconnected, true)
    assert.equal(listeners.size, 0)
  } finally {
    Object.assign(globalThis, previous)
  }
})
