import test from "node:test"
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"

const moduleUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`
const errors = moduleUrl(await readFile(new URL("../js/hooks/audio_error.js", import.meta.url), "utf8"))
const rows = moduleUrl(await readFile(new URL("../js/hooks/audio_track_list.js", import.meta.url), "utf8"))
const code = (await readFile(new URL("../js/hooks/audio_player.js", import.meta.url), "utf8"))
  .replace('import "../../vendor/videojs.min.mjs"', "")
  .replace('"./audio_error"', JSON.stringify(errors))
  .replace('"./audio_track_list"', JSON.stringify(rows))
const {default: hook} = await import(moduleUrl(code))

test("audio controls preserve refresh state, load new generations once and stop on exit", () => {
  let source = "/first"
  let loads = 0
  let pauses = 0
  let plays = 0
  const listeners = new Map()
  const sourceElement = {
    getAttribute: () => source,
    setAttribute: (_name, value) => { source = value },
    removeAttribute: () => { source = null },
  }
  const audio = {
    dataset: {}, controls: true, currentTime: 3,
    querySelector: () => sourceElement,
    replaceWith() {},
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
    load: () => loads++, pause: () => pauses++,
    play: () => { plays++; return Promise.resolve() },
  }
  const originalDocument = globalThis.document
  const documentListeners = new Map()
  const document = {
    createElement: () => ({append() {}}),
    addEventListener: (name, fn) => documentListeners.set(name, fn),
    removeEventListener: name => documentListeners.delete(name),
  }
  const miniPlayer = {
    setAttribute() {},
    focus() { document.activeElement = this },
  }
  const closePlayer = {focus() { document.activeElement = this }}
  const background = {inert: false}
  const pageSibling = {inert: false}
  const root = {
    dataset: {src: "/first", generation: "1", playRequested: "false", stopped: "false", expanded: "false"},
    attributes: {}, listeners: new Map(),
    parentElement: {children: null, parentElement: {children: null}},
    querySelector(selector) {
      if (selector === "audio") return audio
      return selector.includes("collapse") ? closePlayer : miniPlayer
    },
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] },
    addEventListener(name, fn) { this.listeners.set(name, fn) },
    removeEventListener(name) { this.listeners.delete(name) },
    contains(target) { return target === this || target === miniPlayer || target === closePlayer },
  }
  root.parentElement.children = [root, background]
  root.parentElement.parentElement.children = [root.parentElement, pageSibling]
  globalThis.document = {...document, body: root.parentElement.parentElement}
  const context = {
    el: root,
    pushEvent() {},
  }
  try {
    hook.mounted.call(context)
    assert.equal(audio.controls, false)
    hook.updated.call(context)
    assert.equal(loads, 0)
    assert.equal(audio.currentTime, 3)
    Object.assign(context.el.dataset, {src: "/second", generation: "2", playRequested: "true"})
    hook.updated.call(context)
    hook.updated.call(context)
    assert.equal(source, "/second")
    assert.equal(loads, 1)
    assert.equal(plays, 1)
    assert.equal(audio.dataset.generation, "2")
    root.listeners.get("click")({target: {closest: () => ({dataset: {playerAction: "expand"}})}})
    assert.equal(root.attributes.role, "dialog")
    assert.equal(root.attributes["aria-modal"], "true")
    assert.equal(background.inert, true)
    assert.equal(pageSibling.inert, true)
    root.dataset.expanded = "false"
    hook.updated.call(context)
    assert.equal(root.dataset.expanded, "true")
    assert.equal(background.inert, true)
    documentListeners.get("keydown")({key: "Escape"})
    assert.equal(root.dataset.expanded, "false")
    assert.equal(background.inert, false)
    assert.equal(pageSibling.inert, false)
    assert.equal(document.activeElement, miniPlayer)
    hook.destroyed.call(context)
    assert.equal(listeners.size, 0)
    assert.equal(documentListeners.size, 0)
    assert.equal(pauses, 1)
    assert.equal(loads, 2)
    assert.equal(source, null)
  } finally {
    globalThis.document = originalDocument
  }
})
