import test from "node:test"
import assert from "node:assert/strict"
import {connectPlayerDialog} from "../js/music/player/player_dialog.mjs"

function setup() {
  class Node extends EventTarget {
    constructor() { super(); this.dataset = {}; this.hidden = false; this.attrs = {}; this.isConnected = true }
    setAttribute(key, value) { this.attrs[key] = value }
    removeAttribute(key) { delete this.attrs[key] }
    focus() { doc.activeElement = this }
    querySelector(selector) { return nodes[selector] || null }
    querySelectorAll() { return [expand, collapse] }
    getClientRects() { return [1] }
  }
  const doc = new EventTarget()
  doc.defaultView = new EventTarget()
  const host = new Node(), player = new Node(), expand = new Node(), collapse = new Node()
  const nodes = {"#music-player": player, '[data-player-action="expand"]': expand, '[data-player-action="collapse"]': collapse}
  const sibling = {inert: true}, other = {inert: false}
  doc.body = {children: [host, sibling, other]}
  host.parentElement = doc.body
  host.ownerDocument = player.ownerDocument = doc
  return {host, player, expand, collapse, sibling, other, doc}
}

test("dialog collapse returns focus and restores original background inertness", () => {
  const f = setup()
  const dialog = connectPlayerDialog(f.host)
  dialog.expand()
  assert.equal(f.doc.activeElement, f.collapse)
  assert.equal(f.player.attrs.role, "dialog")
  assert.equal(f.other.inert, true)
  dialog.collapse(true)
  assert.equal(f.doc.activeElement, f.expand)
  assert.equal(f.other.inert, false)
  assert.equal(f.sibling.inert, true)
  assert.equal(f.player.attrs.role, "region")
  dialog.destroy()
})

test("destroying an expanded dialog restores inertness and detaches navigation", () => {
  const f = setup()
  let collapsed = 0
  const dialog = connectPlayerDialog(f.host, {onCollapse: () => collapsed++})
  dialog.expand()
  dialog.destroy()
  assert.equal(f.other.inert, false)
  assert.equal(f.sibling.inert, true)
  f.doc.defaultView.dispatchEvent(new Event("phx:page-loading-start"))
  assert.equal(collapsed, 1)
})
