import test from "node:test"
import assert from "node:assert/strict"
import {createMusicSession} from "../js/music/player/session.mjs"

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

test("recent album continuation refuses a vanished track instead of starting at the beginning", async () => {
  const selections = []
  const session = createMusicSession({audio: new FakeAudio(), transport: {
    loadAlbum: async () => ({tracks: [{id: 1, file_id: 11, state: "ready"}]}),
    selectTrack: async value => { selections.push(value); return {track: {id: 1}, src: "/audio/1"} },
  }})
  await session.playAlbum({albumId: 1, trackId: 2, fileId: 12, requireTrack: true})
  assert.equal(session.getSnapshot().error?.code, "unavailable")
  assert.deepEqual(selections, [])
  session.destroy()
})

test("retrying recent album continuation retains its track after an authorization failure", async () => {
  const tracks = [1, 2, 3].map(id => ({id, file_id: id + 10, state: "ready"}))
  const selections = []
  const session = createMusicSession({audio: new FakeAudio(), transport: {
    loadAlbum: async () => ({tracks}),
    selectTrack: async ({trackId}) => {
      selections.push(trackId)
      if (selections.length === 1) throw {code: "unavailable"}
      return {track: tracks[trackId - 1], src: `/audio/${trackId}`}
    },
  }})
  await session.playAlbum({albumId: 1, trackId: 2, fileId: 12, requireTrack: true})
  await session.retry()
  assert.deepEqual(selections, [2, 2])
  assert.equal(session.getSnapshot().selected.id, 2)
  session.destroy()
})

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

test("moving upcoming duplicates changes only their order", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack({trackId, fileId}) { return {track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  await session.appendTrack({trackId: 2, fileId: 12})
  await session.appendTrack({trackId: 2, fileId: 12})
  const before = session.getSnapshot()
  audio.currentTime = 5
  session.moveUpcoming(before.queue[2].entry_id, -1)
  assert.deepEqual(session.getSnapshot().queue.map(track => track.entry_id), [before.queue[0].entry_id, before.queue[2].entry_id, before.queue[1].entry_id])
  session.moveUpcoming(before.queue[2].entry_id, -1)
  session.moveUpcoming(before.queue[0].entry_id, 1)
  assert.deepEqual(session.getSnapshot().queue.map(track => track.entry_id), [before.queue[0].entry_id, before.queue[2].entry_id, before.queue[1].entry_id])
  assert.equal(audio.src, "/music/tracks/1/media/11")
  assert.equal(audio.currentTime, 5)
})

test("successive play-next requests remain FIFO even when responses arrive out of order", async () => {
  const audio = new FakeAudio(), pending = new Map()
  const track = (id, fileId) => ({track: {id, file_id: fileId, title: `Track ${id}`, state: "ready"}, src: `/music/tracks/${id}/media/${fileId}`})
  const session = createMusicSession({audio, transport: {
    selectTrack({trackId, fileId}) {
      if (trackId < 3) return Promise.resolve(track(trackId, fileId))
      return new Promise(resolve => pending.set(trackId, () => resolve(track(trackId, fileId))))
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  await session.appendTrack({trackId: 2, fileId: 12})
  const first = session.playNext({trackId: 3, fileId: 13})
  const second = session.playNext({trackId: 4, fileId: 14})
  pending.get(4)(); pending.get(3)()
  await Promise.all([first, second])
  assert.deepEqual(session.getSnapshot().queue.map(item => item.id), [1, 3, 4, 2])
  assert.equal(audio.src, "/music/tracks/1/media/11")
  assert.equal(audio.playCalls, 1)
})

test("previous restarts after three seconds and otherwise returns to the played entry", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack({trackId, fileId}) { return {track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  await session.appendTrack({trackId: 2, fileId: 12})
  await session.next()
  audio.currentTime = 5
  await session.previous()
  assert.equal(audio.currentTime, 0)
  assert.equal(session.getSnapshot().selected.id, 2)
  await session.previous()
  assert.equal(session.getSnapshot().selected.id, 1)
})

test("a finished session stays stopped when appending and play advances to the new entry", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    async selectTrack({trackId, fileId}) { return {track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  audio.paused = true
  audio.dispatchEvent(new Event("ended"))
  assert.equal(session.getSnapshot().finished, true)
  await session.appendTrack({trackId: 2, fileId: 12})
  assert.equal(audio.paused, true)
  await session.play()
  assert.equal(session.getSnapshot().selected.id, 2)
})

test("previous skips an unavailable entry that was never played", async () => {
  const audio = new FakeAudio()
  const tracks = [{id: 1, file_id: 11, title: "One", state: "ready"}, {id: 2, file_id: 12, title: "Unavailable", state: "missing"}, {id: 3, file_id: 13, title: "Three", state: "ready"}]
  const session = createMusicSession({audio, transport: {
    async loadAlbum() { return {tracks} },
    async selectTrack({trackId, fileId}) { return {track: tracks[trackId - 1], src: `/music/tracks/${trackId}/media/${fileId}`} },
  }})
  await session.playAlbum({albumId: 1, libraryId: null})
  await session.next()
  await session.next()
  assert.equal(session.getSnapshot().selected.id, 3)
  await session.previous()
  assert.equal(session.getSnapshot().selected.id, 1)
})

test("replacing an album keeps the existing audio until its first track is authorized", async () => {
  const audio = new FakeAudio()
  let finishSelection
  const row = id => ({id, file_id: id + 10, title: `Track ${id}`, state: "ready"})
  const session = createMusicSession({audio, transport: {
    async loadAlbum({albumId}) { return {tracks: [row(albumId)]} },
    selectTrack({trackId, fileId}) {
      const result = {track: row(trackId), src: `/music/tracks/${trackId}/media/${fileId}`}
      return trackId === 2 ? new Promise(resolve => { finishSelection = () => resolve(result) }) : Promise.resolve(result)
    },
  }})
  await session.playAlbum({albumId: 1, libraryId: null})
  audio.currentTime = 4
  const pending = session.playAlbum({albumId: 2, libraryId: null})
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(audio.src, "/music/tracks/1/media/11")
  assert.equal(audio.paused, false)
  assert.equal(audio.currentTime, 4)
  finishSelection()
  await pending
  assert.equal(audio.src, "/music/tracks/2/media/12")
})

test("an append requested during replacement belongs to the new session", async () => {
  const audio = new FakeAudio()
  let finishReplacement
  const row = id => ({id, file_id: id + 10, title: `Track ${id}`, state: "ready"})
  const session = createMusicSession({audio, transport: {
    selectTrack({trackId, fileId}) {
      const result = {track: row(trackId), src: `/music/tracks/${trackId}/media/${fileId}`}
      return trackId === 2 ? new Promise(resolve => { finishReplacement = () => resolve(result) }) : Promise.resolve(result)
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  const replacement = session.selectTrack({trackId: 2, fileId: 12})
  const append = session.appendTrack({trackId: 3, fileId: 13})
  await new Promise(resolve => setImmediate(resolve))
  finishReplacement()
  await Promise.all([replacement, append])
  assert.deepEqual(session.getSnapshot().queue.map(item => item.id), [2, 3])
})

test("an old track ending during a failed replacement is handled once", async () => {
  const audio = new FakeAudio()
  let rejectReplacement
  const session = createMusicSession({audio, transport: {
    selectTrack({trackId, fileId}) {
      if (trackId === 2) return new Promise((_, reject) => { rejectReplacement = reject })
      return Promise.resolve({track: {id: trackId, file_id: fileId, title: "Track", state: "ready"}, src: `/music/tracks/${trackId}/media/${fileId}`})
    },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  const replacement = session.selectTrack({trackId: 2, fileId: 12})
  audio.paused = true
  audio.dispatchEvent(new Event("ended"))
  rejectReplacement(Object.assign(new Error("unavailable"), {code: "unavailable"}))
  await replacement
  assert.equal(session.getSnapshot().finished, true)
})

test("reports actual playback once and reports again after replay", async () => {
  let now = 0
  const audio = new FakeAudio()
  const reports = []
  const session = createMusicSession({audio, clock: () => now, transport: {
    async selectTrack() { return {track: {id: 1, file_id: 11, title: "Track", duration_ms: 20_000, state: "ready"}, src: "/music/tracks/1/media/11"} },
    async recordActivity(track) { reports.push(track) },
  }})
  await session.selectTrack({trackId: 1, fileId: 11})
  now = 9; audio.currentTime = 9; audio.dispatchEvent(new Event("timeupdate"))
  assert.equal(reports.length, 0)
  now = 10; audio.currentTime = 10; audio.dispatchEvent(new Event("timeupdate"))
  assert.deepEqual(reports, [{trackId: 1, fileId: 11}])
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(session.getSnapshot().activityRevision, 1)
  now = 20; audio.currentTime = 20; audio.dispatchEvent(new Event("ended"))
  session.play()
  now = 30; audio.currentTime = 10; audio.dispatchEvent(new Event("timeupdate"))
  assert.equal(reports.length, 2)
  session.previous()
  audio.dispatchEvent(new Event("seeked"))
  now = 40; audio.currentTime = 10; audio.dispatchEvent(new Event("timeupdate"))
  assert.equal(reports.length, 3)
})

test("only declared playback commands are exposed", () => {
  const session = createMusicSession({audio: new FakeAudio(), transport: {}})
  assert.equal(typeof session.playAlbum, "function")
  assert.equal(session.playUnknownAlbum, undefined)
  assert.equal(session.playFromHere, undefined)
  session.destroy()
})

for (const start of [{trackId: 2, fileId: 12}, {startIndex: 1}]) {
  test(`album start uses canonical selection ${JSON.stringify(start)}`, async () => {
    const tracks = [1, 2, 3].map(id => ({id, file_id: id + 10, state: "ready"}))
    const session = createMusicSession({audio: new FakeAudio(), transport: {
      loadAlbum: async () => ({tracks}),
      selectTrack: async ({trackId}) => ({track: tracks[trackId - 1], src: `/audio/${trackId}`}),
    }})
    await session.playAlbum({albumId: 1, ...start})
    assert.equal(session.getSnapshot().selected.id, 2)
    assert.deepEqual(session.getSnapshot().queue.map(track => track.id), [2, 3])
    session.destroy()
  })
}

test("album authorization failure currently retries from the album beginning", async () => {
  const tracks = [1, 2].map(id => ({id, file_id: id + 10, state: "ready"}))
  let fail = true
  const session = createMusicSession({audio: new FakeAudio(), transport: {
    loadAlbum: async () => ({tracks}),
    selectTrack: async ({trackId}) => {
      if (fail) throw Object.assign(new Error(), {code: "unavailable"})
      return {track: tracks[trackId - 1], src: `/audio/${trackId}`}
    },
  }})
  await session.playAlbum({albumId: 1, trackId: 2, fileId: 12})
  fail = false
  await session.retry()
  assert.equal(session.getSnapshot().selected.id, 1)
  session.destroy()
})

test("a late play rejection cannot fail a replacement source", async () => {
  const audio = new FakeAudio()
  const session = createMusicSession({audio, transport: {
    selectTrack: async ({trackId, fileId}) => ({track: {id: trackId, file_id: fileId}, src: `/audio/${trackId}`}),
  }})
  let rejectPlay
  audio.play = () => new Promise((_, reject) => { rejectPlay = reject })
  const outgoing = session.selectTrack({trackId: 1, fileId: 11})
  await new Promise(resolve => setImmediate(resolve))
  audio.play = FakeAudio.prototype.play
  await session.selectTrack({trackId: 2, fileId: 12})
  rejectPlay(Object.assign(new Error(), {name: "NotAllowedError"}))
  await outgoing
  assert.equal(session.getSnapshot().selected.id, 2)
  assert.equal(session.getSnapshot().error, null)
  session.destroy()
})

test("a late authorization response cannot revive a destroyed session", async () => {
  const audio = new FakeAudio()
  let resolveSelection
  const session = createMusicSession({audio, transport: {selectTrack: () => new Promise(resolve => { resolveSelection = resolve })}})
  const pending = session.selectTrack({trackId: 1, fileId: 11})
  session.destroy()
  resolveSelection({track: {id: 1, file_id: 11}, src: "/audio/1"})
  await pending
  assert.equal(audio.src, "")
  assert.equal(audio.playCalls, 0)
  assert.equal(session.getSnapshot().selected, null)
})

test("destroyed sessions reject queue additions without reviving their queue", async () => {
  const track = {id: 1, file_id: 11, state: "ready"}
  const session = createMusicSession({audio: new FakeAudio(), transport: {
    selectTrack: async () => ({track, src: "/audio/1"}),
    loadAlbum: async () => ({tracks: [track]}),
  }})
  session.destroy()
  assert.equal(await session.appendTrack({trackId: 1, fileId: 11}), false)
  assert.equal(await session.playNext({trackId: 1, fileId: 11}), false)
  assert.equal(await session.appendAlbum({albumId: 1}), false)
  assert.deepEqual(session.getSnapshot().queue, [])
})

test("a stale album response cannot replace the later authorized album", async () => {
  const pending = new Map(), authorized = []
  const session = createMusicSession({audio: new FakeAudio(), transport: {
    loadAlbum: ({albumId}) => new Promise(resolve => pending.set(albumId, resolve)),
    selectTrack: async ({trackId}) => {
      authorized.push(trackId)
      return {track: {id: trackId, file_id: trackId + 10}, src: `/audio/${trackId}`}
    },
  }})
  const first = session.playAlbum({albumId: 1})
  const second = session.playAlbum({albumId: 2})
  pending.get(2)({tracks: [{id: 2, file_id: 12, state: "ready"}]})
  await second
  pending.get(1)({tracks: [{id: 1, file_id: 11, state: "ready"}]})
  await first
  assert.deepEqual(authorized, [2])
  assert.equal(session.getSnapshot().selected.id, 2)
  assert.deepEqual(session.getSnapshot().queue.map(track => track.id), [2])
  session.destroy()
})

test("an authorization refusal clears the outgoing source and queue", async () => {
  const audio = new FakeAudio()
  let refused = false
  const session = createMusicSession({audio, transport: {
    loadAlbum: async () => ({tracks: [{id: 1, file_id: 11, state: "ready"}]}),
    selectTrack: async ({trackId, fileId}) => {
      if (refused) throw Object.assign(new Error(), {code: "unauthenticated"})
      return {track: {id: trackId, file_id: fileId}, src: `/audio/${trackId}`}
    },
  }})
  await session.playAlbum({albumId: 1})
  refused = true
  await session.selectTrack({trackId: 2, fileId: 12})
  assert.equal(session.getSnapshot().selected, null)
  assert.deepEqual(session.getSnapshot().queue, [])
  assert.equal(audio.src, "")
  assert.equal(audio.paused, true)
  session.destroy()
})

test("invalid selection input preserves asynchronous rejection at the public API", async () => {
  const session = createMusicSession({audio: new FakeAudio(), transport: {}})
  for (const method of ["selectTrack", "playAlbum"]) {
    let request
    assert.doesNotThrow(() => { request = session[method](null) })
    await assert.rejects(request, TypeError)
  }
  session.destroy()
})
