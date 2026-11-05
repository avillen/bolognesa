import test from "node:test"
import assert from "node:assert/strict"
import {initializeMusicPlayer as initialize} from "../js/music/music_bootstrap.mjs"
import {createMediaCoordinator} from "../js/shared/media_coordinator.mjs"
const initializeMusicPlayer = (document, options) => initialize(document, {...options, coordinator: createMediaCoordinator()})


class Node {
  constructor() { this.children = []; this.hidden = true; this.dataset = {}; this.listeners = new Map(); this.style = {setProperty() {}, removeProperty() {}} }
  querySelector(selector) { return this.nodes?.[selector] || null }
  closest() { return null }
  append(node) { this.children.push(node) }
  setAttribute(name, value) { this[name] = value }
  pause() { this.paused = true; this.dispatch("pause") }
  load() {}
  removeAttribute() {}
  focus() {}
  querySelectorAll() { return [] }
  play() { this.paused = false; this.dispatch("playing"); return Promise.resolve() }
  addEventListener(name, callback) { if (!this.listeners.has(name)) this.listeners.set(name, new Set()); this.listeners.get(name).add(callback) }
  removeEventListener(name, callback) { this.listeners.get(name)?.delete(callback) }
  dispatch(name) { for (const callback of this.listeners.get(name) || []) callback({type: name}) }
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

test("external play and pause control the current audio and follow its state", async () => {
  const host = new Node(), audio = new Node(), player = new Node()
  audio.paused = true
  host.nodes = {"#music-playback": audio, "#music-player": player, "#now-playing": new Node(), "[data-player-artist]": new Node(), "#audio-error": new Node(), "[data-player-loading]": new Node(), "#music-player-seek": new Node(), "#queue-position": new Node(), "#queue-finished": new Node(), "[data-player-time]": new Node()}
  for (const action of ["toggle", "seek", "previous", "next", "retry", "expand", "collapse"]) host.nodes[`[data-player-action="${action}"]`] = new Node()
  player.nodes = host.nodes
  const handlers = {}
  const mediaSession = {setActionHandler(action, handler) { handlers[action] = handler }}
  const document = {body: new Node(), addEventListener() {}, removeEventListener() {}, querySelector: () => host, createElement: () => new Node(), defaultView: {navigator: {mediaSession}, addEventListener() {}, removeEventListener() {}}}
  player.ownerDocument = host.ownerDocument = document
  const transport = {selectTrack: async () => ({track: {id: 1, file_id: 1, title: "Track"}, src: "/audio"})}
  const instance = initializeMusicPlayer(document, {transport})
  await instance.session.selectTrack({trackId: 1, fileId: 1})
  assert.equal(mediaSession.playbackState, "playing")
  handlers.pause()
  assert.equal(instance.session.getSnapshot().paused, true)
  assert.equal(mediaSession.playbackState, "paused")
  audio.play = () => Promise.reject(Object.assign(new Error(), {name: "NotAllowedError"}))
  handlers.play()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(mediaSession.playbackState, "paused")
  assert.equal(instance.session.getSnapshot().error.code, "autoplay_blocked")
  audio.play = Node.prototype.play
  handlers.play()
  assert.equal(instance.session.getSnapshot().paused, false)
  assert.equal(mediaSession.playbackState, "playing")
  const video = new Node()
  video.paused = false
  instance.coordinator.register(video)
  video.dispatch("playing")
  assert.equal(instance.session.getSnapshot().paused, true)
  assert.equal(handlers.play, null)
  assert.equal(handlers.pause, null)
  assert.equal(mediaSession.playbackState, "none")
  instance.session.play()
  assert.equal(mediaSession.playbackState, "playing")
  instance.session.clear()
  assert.equal(mediaSession.playbackState, "none")
  instance.destroy()
  assert.equal(handlers.play, null)
  assert.equal(handlers.pause, null)
})

test("unsupported media actions do not prevent playback or cleanup", async () => {
  const host = new Node(), audio = new Node(), player = new Node()
  audio.paused = true
  host.nodes = {"#music-playback": audio, "#music-player": player, "#now-playing": new Node(), "[data-player-artist]": new Node(), "#audio-error": new Node(), "[data-player-loading]": new Node(), "#music-player-seek": new Node(), "#queue-position": new Node(), "#queue-finished": new Node(), "[data-player-time]": new Node()}
  for (const action of ["toggle", "seek", "previous", "next", "retry", "expand", "collapse"]) host.nodes[`[data-player-action="${action}"]`] = new Node()
  player.nodes = host.nodes
  const mediaSession = {setActionHandler() { throw new Error("unsupported") }}
  const document = {body: new Node(), addEventListener() {}, removeEventListener() {}, querySelector: () => host, createElement: () => new Node(), defaultView: {navigator: {mediaSession}, addEventListener() {}, removeEventListener() {}}}
  player.ownerDocument = host.ownerDocument = document
  const instance = initializeMusicPlayer(document, {transport: {selectTrack: async () => ({track: {id: 1, file_id: 1}, src: "/audio"})}})
  await instance.session.selectTrack({trackId: 1, fileId: 1})
  assert.equal(instance.session.getSnapshot().paused, false)
  instance.destroy()
})

test("external track controls follow the album queue and update metadata", async () => {
  const host = new Node(), audio = new Node(), player = new Node()
  audio.paused = true
  host.nodes = {"#music-playback": audio, "#music-player": player, "#now-playing": new Node(), "[data-player-artist]": new Node(), "#audio-error": new Node(), "[data-player-loading]": new Node(), "#music-player-seek": new Node(), "#queue-position": new Node(), "#queue-finished": new Node(), "[data-player-time]": new Node()}
  for (const action of ["toggle", "seek", "previous", "next", "retry", "expand", "collapse"]) host.nodes[`[data-player-action="${action}"]`] = new Node()
  player.nodes = host.nodes
  const handlers = {}
  const mediaSession = {setActionHandler(action, handler) { handlers[action] = handler }}
  const document = {body: new Node(), addEventListener() {}, removeEventListener() {}, querySelector: () => host, createElement: () => new Node(), defaultView: {navigator: {mediaSession}, MediaMetadata: class { constructor(data) { Object.assign(this, data) } }, addEventListener() {}, removeEventListener() {}}}
  player.ownerDocument = host.ownerDocument = document
  const tracks = [1, 2, 3].map(id => ({id, file_id: id, title: `Track ${id}`, artist: "Artist", album: "Album", state: "ready"}))
  const transport = {loadAlbum: async () => ({tracks}), selectTrack: async ({trackId}) => ({track: tracks[trackId - 1], src: `/audio/${trackId}`})}
  const instance = initializeMusicPlayer(document, {transport})
  await instance.session.playAlbum({albumId: 1})
  assert.equal(typeof handlers.previoustrack, "function")
  assert.equal(typeof handlers.nexttrack, "function")
  await handlers.nexttrack()
  assert.equal(instance.session.getSnapshot().selected.id, 2)
  assert.equal(mediaSession.metadata.title, "Track 2")
  assert.equal(typeof handlers.previoustrack, "function")
  await handlers.nexttrack()
  assert.equal(mediaSession.metadata.title, "Track 3")
  assert.equal(handlers.nexttrack, null)
  await handlers.previoustrack()
  assert.equal(mediaSession.metadata.title, "Track 2")
  const video = new Node()
  video.paused = false
  instance.coordinator.register(video)
  video.dispatch("playing")
  assert.equal(handlers.previoustrack, null)
  assert.equal(handlers.nexttrack, null)
  instance.session.play()
  assert.equal(typeof handlers.previoustrack, "function")
  assert.equal(typeof handlers.nexttrack, "function")
  await instance.session.selectTrack({trackId: 1, fileId: 1})
  assert.equal(typeof handlers.previoustrack, "function")
  assert.equal(handlers.nexttrack, null)
  instance.destroy()
})
