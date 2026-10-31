import test from "node:test"
import assert from "node:assert/strict"
import {createMusicSession} from "../js/music/music_bootstrap/session.mjs"

class FakeAudio extends EventTarget {
  constructor() {
    super()
    this.paused = true
    this.currentTime = 0
    this.duration = 20
    this.src = ""
    this.loads = 0
    this.playCalls = 0
  }
  load() { this.loads++ }
  async play() { this.playCalls++; this.paused = false; this.dispatchEvent(new Event("playing")) }
  pause() { this.paused = true; this.dispatchEvent(new Event("pause")) }
  removeAttribute(name) { if (name === "src") this.src = "" }
}

test("screen subscribers can detach and reattach without changing the document audio", async () => {
  const audio = new FakeAudio()
  const transport = {
    async selectTrack() {
      return {track: {id: 3, file_id: 8, title: "Track", artist: "Artist", album: "Album", duration_ms: 20_000, state: "ready"}, src: "/music/tracks/3/media/8"}
    },
    async loadAlbum() { return {tracks: []} },
  }
  const session = createMusicSession({audio, transport})
  const first = session.subscribe(() => {})
  await session.selectTrack({trackId: 3, fileId: 8})
  audio.currentTime = 7
  audio.pause()
  first()
  session.subscribe(() => {})
  assert.equal(session.getSnapshot().selected.id, 3)
  assert.equal(session.getSnapshot().position, 7)
  assert.equal(session.getSnapshot().paused, true)
  assert.equal(audio.src, "/music/tracks/3/media/8")
  assert.equal(audio.loads, 1)
})

test("an ended queue source authorizes its next track once", async () => {
  const audio = new FakeAudio()
  const selections = []
  const rows = [1, 2].map(id => ({id, file_id: id + 10, title: `Track ${id}`, state: "ready"}))
  const transport = {
    async loadAlbum() { return {tracks: rows} },
    async selectTrack({trackId, fileId}) {
      selections.push(trackId)
      return {track: rows[trackId - 1], src: `/music/tracks/${trackId}/media/${fileId}`}
    },
  }
  const session = createMusicSession({audio, transport})
  const finishedSnapshots = []
  session.subscribe(snapshot => finishedSnapshots.push(snapshot.finished))
  await session.playAlbum({albumId: 4, libraryId: null})
  assert.deepEqual(selections, [1])
  audio.dispatchEvent(new Event("ended"))
  audio.dispatchEvent(new Event("ended"))
  await new Promise(resolve => setImmediate(resolve))
  assert.deepEqual(selections, [1, 2])
  assert.equal(session.getSnapshot().queueIndex, 1)
  assert.equal(finishedSnapshots.includes(true), false)
})

test("clearing invalidates a pending track response", async () => {
  const audio = new FakeAudio()
  let resolveSelection
  const session = createMusicSession({audio, transport: {
    selectTrack: () => new Promise(resolve => { resolveSelection = resolve }),
    loadAlbum: async () => ({tracks: []}),
  }})
  const pending = session.selectTrack({trackId: 3, fileId: 8})
  session.clear()
  resolveSelection({track: {id: 3, file_id: 8, title: "Late", state: "ready"}, src: "/music/tracks/3/media/8"})
  await pending
  assert.equal(session.getSnapshot().selected, null)
  assert.equal(audio.src, "")
})

test("a failed individual selection keeps the current source and retry reauthorizes it", async () => {
  const audio = new FakeAudio()
  let fail = false
  const calls = []
  const transport = {
    async selectTrack({trackId, fileId}) {
      calls.push(trackId)
      if (fail) { const error = new Error(); error.code = "unavailable"; throw error }
      return {track: {id: trackId, file_id: fileId, title: `Track ${trackId}`, state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`}
    },
    async loadAlbum() { return {tracks: []} },
  }
  const session = createMusicSession({audio, transport})
  await session.selectTrack({trackId: 1, fileId: 11})
  fail = true
  await session.selectTrack({trackId: 2, fileId: 12})
  assert.equal(session.getSnapshot().selected.id, 1)
  assert.equal(audio.src, "/music/tracks/1/media/11")
  fail = false
  await session.retry()
  assert.deepEqual(calls, [1, 2, 2])
  assert.equal(session.getSnapshot().selected.id, 2)
})

test("a native media error is visible and keeps the selected track retryable", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack() { return {track: {id: 1, file_id: 11, title: "Track", state: "ready"}, src: "/music/tracks/1/media/11"} },
    async loadAlbum() { return {tracks: []} },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  audio.dispatchEvent(new Event("error"))
  assert.deepEqual(session.getSnapshot().error, {code: "playback_failed", retryable: true})
  assert.equal(session.getSnapshot().selected.id, 1)
})
