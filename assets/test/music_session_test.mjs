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

test("appending duplicate tracks preserves paused single-track playback", async () => {
  const audio = new FakeAudio()
  const transport = {
    async selectTrack({trackId, fileId}) {
      return {track: {id: trackId, file_id: fileId, title: `Track ${trackId}`, state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`}
    },
    async loadAlbum() { return {tracks: []} },
  }
  const session = createMusicSession({audio, transport})
  await session.selectTrack({trackId: 1, fileId: 11})
  audio.currentTime = 7
  audio.pause()
  await session.appendTrack({trackId: 2, fileId: 12})
  await session.appendTrack({trackId: 2, fileId: 12})
  const snapshot = session.getSnapshot()
  assert.deepEqual(snapshot.queue.map(track => track.id), [1, 2, 2])
  assert.notEqual(snapshot.queue[1].entry_id, snapshot.queue[2].entry_id)
  assert.equal(snapshot.queueIndex, 0)
  assert.equal(audio.src, "/music/tracks/1/media/11")
  assert.equal(audio.currentTime, 7)
  assert.equal(audio.paused, true)
  assert.equal(audio.playCalls, 1)
})

test("queued track plays after the current individual track ends", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack({trackId, fileId}) {
      return {track: {id: trackId, file_id: fileId, title: `Track ${trackId}`, state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`}
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  await session.appendTrack({trackId: 2, fileId: 12})
  audio.dispatchEvent(new Event("ended"))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(session.getSnapshot().selected.id, 2)
  assert.equal(audio.src, "/music/tracks/2/media/12")
})

test("a pending append cannot change a replacement session", async () => {
  const audio = new FakeAudio()
  let resolveAppend
  const session = createMusicSession({audio, transport: {
    selectTrack({trackId, fileId}) {
      if (trackId === 2) return new Promise(resolve => { resolveAppend = resolve })
      return Promise.resolve({track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`})
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  const pending = session.appendTrack({trackId: 2, fileId: 12})
  await session.selectTrack({trackId: 3, fileId: 13})
  resolveAppend({track: {id: 2, file_id: 12, title: "Track", state: "ready"}, src: "/music/tracks/2/media/12"})
  assert.equal(await pending, false)
  assert.equal(session.getSnapshot().selected.id, 3)
  assert.deepEqual(session.getSnapshot().queue, [])
})

test("rapid track appends retain request order when responses arrive out of order", async () => {
  const audio = new FakeAudio()
  const resolves = new Map()
  const session = createMusicSession({audio, transport: {
    selectTrack({trackId, fileId}) {
      if (trackId === 1) return Promise.resolve({track: {id: 1, file_id: 11, title: "One", state: "ready"}, src: "/music/tracks/1/media/11"})
      return new Promise(resolve => resolves.set(trackId, () => resolve({track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`})))
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  const first = session.appendTrack({trackId: 2, fileId: 12})
  const second = session.appendTrack({trackId: 3, fileId: 13})
  resolves.get(3)()
  resolves.get(2)()
  await Promise.all([first, second])
  assert.deepEqual(session.getSnapshot().queue.map(track => track.id), [1, 2, 3])
})

test("tracks queued before playback wait until play is requested", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack({trackId, fileId}) { return {track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.appendTrack({trackId: 2, fileId: 12})
  assert.equal(audio.playCalls, 0)
  await session.play()
  assert.equal(session.getSnapshot().selected.id, 2)
  assert.equal(audio.src, "/music/tracks/2/media/12")
})

test("albums appended in request order continue after the current album", async () => {
  const audio = new FakeAudio()
  const pending = new Map()
  const row = id => ({id, file_id: id + 10, title: `Track ${id}`, state: "ready"})
  const session = createMusicSession({audio, transport: {
    loadAlbum({albumId}) {
      if (albumId === 1) return Promise.resolve({tracks: [row(1)]})
      return new Promise(resolve => pending.set(albumId, resolve))
    },
    async selectTrack({trackId, fileId}) { return {track: row(trackId), src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.playAlbum({albumId: 1, libraryId: null})
  const second = session.appendAlbum({albumId: 2, libraryId: null})
  const third = session.appendAlbum({albumId: 3, libraryId: null})
  pending.get(3)({tracks: [row(4)]})
  pending.get(2)({tracks: [row(2), row(3)]})
  await Promise.all([second, third])
  assert.deepEqual(session.getSnapshot().queue.map(track => track.id), [1, 2, 3, 4])
  assert.equal(audio.src, "/music/tracks/1/media/11")
  audio.dispatchEvent(new Event("ended"))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(session.getSnapshot().selected.id, 2)
  audio.dispatchEvent(new Event("ended"))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(session.getSnapshot().selected.id, 3)
  audio.dispatchEvent(new Event("ended"))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(session.getSnapshot().selected.id, 4)
  audio.dispatchEvent(new Event("ended"))
  assert.equal(session.getSnapshot().finished, true)
})

test("removing one upcoming duplicate and clearing upcoming preserve paused playback", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack({trackId, fileId}) { return {track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  await session.appendTrack({trackId: 2, fileId: 12})
  await session.appendTrack({trackId: 2, fileId: 12})
  audio.currentTime = 7
  audio.pause()
  const before = session.getSnapshot()
  session.removeUpcoming(before.queue[1].entry_id)
  assert.deepEqual(session.getSnapshot().queue.map(track => track.entry_id), [before.queue[0].entry_id, before.queue[2].entry_id])
  session.removeUpcoming(before.queue[0].entry_id)
  assert.equal(session.getSnapshot().queue.length, 2)
  session.clearUpcoming()
  assert.equal(session.getSnapshot().queue.length, 1)
  assert.equal(audio.src, "/music/tracks/1/media/11")
  assert.equal(audio.currentTime, 7)
  assert.equal(audio.paused, true)
})

test("clearing upcoming ignores an earlier pending append", async () => {
  const audio = new FakeAudio()
  let finishAppend
  const session = createMusicSession({audio, transport: {
    selectTrack({trackId, fileId}) {
      if (trackId === 2) return new Promise(resolve => { finishAppend = resolve })
      return Promise.resolve({track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`})
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  const pending = session.appendTrack({trackId: 2, fileId: 12})
  session.clearUpcoming()
  finishAppend({track: {id: 2, file_id: 12, title: "Track", state: "ready"}, src: "/music/tracks/2/media/12"})
  assert.equal(await pending, false)
  assert.deepEqual(session.getSnapshot().queue, [])
})
