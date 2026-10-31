import test from "node:test"
import assert from "node:assert/strict"
import {initializeMusicPlayer} from "../js/music/music_bootstrap.mjs"

class Node {
  constructor() { this.children = []; this.hidden = true; this.dataset = {}; this.listeners = new Map(); this.style = {setProperty() {}, removeProperty() {}} }
  querySelector(selector) { return this.nodes?.[selector] || null }
  closest() { return null }
  append(node) { this.children.push(node) }
  setAttribute(name, value) { this[name] = value }
  pause() { this.paused = true }
  load() {}
  removeAttribute() {}
  focus() {}
  querySelectorAll() { return [] }
  play() { return Promise.resolve() }
  addEventListener(name, callback) { this.listeners.set(name, callback) }
  removeEventListener(name) { this.listeners.delete(name) }
  replaceWith(node) { this.parent = node }
}

test("bootstrap initializes an authenticated host once and reuses its audio session", () => {
  const host = new Node(), audio = new Node(), player = new Node()
  host.nodes = {"#music-playback": audio, "#music-player": player, "#now-playing": new Node(), "[data-player-artist]": new Node(), "#audio-error": new Node(), "[data-player-loading]": new Node(), "#music-player-seek": new Node(), '[data-player-action="seek"]': null, "#queue-position": new Node(), "#queue-finished": new Node(), "[data-player-time]": new Node(), '[data-player-action="toggle"]': new Node(), '[data-player-action="previous"]': new Node(), '[data-player-action="next"]': new Node(), '[data-player-action="retry"]': new Node(), '[data-player-action="expand"]': new Node(), '[data-player-action="collapse"]': new Node()}
  host.nodes['[data-player-action="seek"]'] = host.nodes["#music-player-seek"]
  player.nodes = {'[data-player-action="toggle"]': host.nodes['[data-player-action="toggle"]'], '[data-player-action="seek"]': host.nodes["#music-player-seek"], '[data-player-action="previous"]': host.nodes['[data-player-action="previous"]'], '[data-player-action="next"]': host.nodes['[data-player-action="next"]'], '[data-player-action="retry"]': host.nodes['[data-player-action="retry"]']}
  const document = {body: new Node(), activeElement: null, addEventListener() {}, removeEventListener() {}, querySelector: selector => selector === "#music-player-host" ? host : null, createElement: () => new Node(), defaultView: {addEventListener() {}, removeEventListener() {}}}
  player.ownerDocument = document
  host.ownerDocument = document
  const transport = {selectTrack: async () => ({}), loadAlbum: async () => ({tracks: []})}
  const first = initializeMusicPlayer(document, {transport})
  const second = initializeMusicPlayer(document, {transport})
  assert.equal(first, second)
  assert.equal(first.audio, audio)
  first.destroy()
})

test("bootstrap returns null when the public page has no authenticated host", () => {
  assert.equal(initializeMusicPlayer({querySelector: () => null}, {}), null)
})

test("publishes selected track metadata and clears it with the playback owner", async () => {
  const host = new Node(), audio = new Node(), player = new Node()
  host.nodes = {"#music-playback": audio, "#music-player": player, "#now-playing": new Node(), "[data-player-artist]": new Node(), "#audio-error": new Node(), "[data-player-loading]": new Node(), "#music-player-seek": new Node(), "#queue-position": new Node(), "#queue-finished": new Node(), "[data-player-time]": new Node()}
  for (const action of ["toggle", "seek", "previous", "next", "retry", "expand", "collapse"]) host.nodes[`[data-player-action="${action}"]`] = new Node()
  player.nodes = host.nodes
  const mediaSession = {metadata: null}
  const document = {body: new Node(), addEventListener() {}, removeEventListener() {}, querySelector: () => host, createElement: () => new Node(), defaultView: {navigator: {mediaSession}, MediaMetadata: class { constructor(data) { Object.assign(this, data) } }, addEventListener() {}, removeEventListener() {}}}
  player.ownerDocument = host.ownerDocument = document
  const transport = {selectTrack: async ({trackId}) => ({track: {id: trackId, file_id: 1, title: `Track ${trackId}`, artist: "Artist", album: "Album"}, src: "/audio"})}
  const instance = initializeMusicPlayer(document, {transport})
  await instance.session.selectTrack({trackId: 1, fileId: 1})
  assert.equal(mediaSession.metadata?.title, "Track 1")
  assert.equal(mediaSession.metadata.artist, "Artist")
  assert.equal(mediaSession.metadata.album, "Album")
  assert.deepEqual(mediaSession.metadata.artwork, [{src: "/images/bolognesa-cat.svg", type: "image/svg+xml"}])
  await instance.session.selectTrack({trackId: 2, fileId: 1})
  assert.equal(mediaSession.metadata.title, "Track 2")
  instance.session.clear()
  assert.equal(mediaSession.metadata, null)
  instance.destroy()
})
