import test from "node:test"
import assert from "node:assert/strict"
import {queueGroups} from "../js/music/music_bootstrap/queue_view.mjs"

test("queue groups only consecutive upcoming entries and retains duplicates", () => {
  const track = (id, album) => ({id, entry_id: id, title: `Track ${id}`, artist: "Artist", album})
  const snapshot = {selected: track(1, "A"), queueIndex: 0, queue: [track(1, "A"), track(2, "A"), track(3, "B"), track(2, "A")]}
  assert.deepEqual(queueGroups(snapshot).map(group => [group.album, group.tracks.map(item => item.id)]), [["A", [2]], ["B", [3]], ["A", [2]]])
})

test("a pending queue without a current track shows every entry", () => {
  assert.equal(queueGroups({selected: null, queueIndex: -1, queue: [{id: 1, title: "One"}]}).flatMap(group => group.tracks).length, 1)
})

test("rendering shows the current track and upcoming album without interpreting titles as HTML", async () => {
  const {renderQueue} = await import("../js/music/music_bootstrap/queue_view.mjs")
  class Element {
    constructor() { this.children = []; this.textContent = ""; this.hidden = false; this.dataset = {} }
    append(child) { this.children.push(child) }
    replaceChildren(...children) { this.children = children }
    setAttribute(name, value) { this[name] = value }
  }
  const current = new Element(), list = new Element(), empty = new Element()
  const panel = {dataset: {noCurrent: "Nothing playing", removeLabel: "Remove"}, ownerDocument: {createElement: () => new Element()}, querySelector: selector => ({"[data-queue-current]": current, "[data-queue-list]": list, "[data-queue-empty]": empty})[selector]}
  renderQueue(panel, {selected: {title: "Current"}, queueIndex: 0, queue: [{title: "Current"}, {title: "<script>", album: "Album", artist: "Artist"}]})
  assert.equal(current.textContent, "Current")
  assert.equal(list.children[0].children[0].textContent, "Album · Artist")
  assert.equal(list.children[0].children[1].children[0].children[0].textContent, "<script>")
  assert.equal(empty.hidden, true)
})
