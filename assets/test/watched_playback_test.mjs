import test from "node:test"
import assert from "node:assert/strict"
import {createWatchedPlayback} from "../js/video/player/watched_playback.mjs"

class Video extends EventTarget {
  constructor() { super(); this.currentTime = 0; this.duration = 500; this.paused = false; this.seeking = false; this.ended = false; this.dataset = {} }
}

test("uses whole-file HLS time and ignores preparation and stale sources", () => {
  let now = 0
  const reports = [], video = new Video()
  const watched = createWatchedPlayback({video, clock: () => now, report: report => reports.push(report)})
  const config = {attemptId: "a", fileId: "7", playbackPhase: "ready"}
  Object.assign(video.dataset, config)
  watched.update(config)
  video.fileTimeline = {offset: 330, duration: 500}
  for (let i = 0; i <= 120; i++) {
    now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate"))
  }
  assert.deepEqual(reports, [{attempt_id: "a", file_id: "7"}])
  watched.update({...config, attemptId: "b", playbackPhase: "preparing"})
  for (let i = 0; i <= 150; i++) { now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate")) }
  assert.equal(reports.length, 1)
  watched.update({...config, attemptId: "c"}) // old video dataset must not qualify
  for (let i = 0; i <= 150; i++) { now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate")) }
  assert.equal(reports.length, 1)
  watched.destroy()
  assert.equal(reports.length, 1)
})

test("records before the source controller advances on ended and detaches on teardown", async () => {
  const {createSourceController} = await import("../js/video/player/source_controller.mjs")
  let now = 0
  const events = [], video = new Video()
  video.pause = () => { video.paused = true }
  video.load = () => {}
  video.removeAttribute = () => {}
  const el = {dataset: {attemptId: "a", fileId: "7", playbackPhase: "ready",
    videoId: "video-7", recoveryScope: "scope", src: "/episode"}}
  const watched = createWatchedPlayback({video, clock: () => now, report: () => events.push("watched")})
  const recovery = {suspend() {}, beforeSourceChange() {}, source: () => true, ready() {}}
  const source = createSourceController({video, el, recovery, watched, pushEvent: name => events.push(name)}, {})
  watched.update(el.dataset)
  source.update()
  video.paused = false
  video.duration = 1000
  for (let i = 0; i <= 120; i++) { now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate")) }
  assert.deepEqual(events, [])
  video.ended = true
  video.dispatchEvent(new Event("ended"))
  assert.deepEqual(events, ["watched", "playback_ended"])
  watched.destroy()
  source.destroy()
  video.dispatchEvent(new Event("ended"))
  assert.deepEqual(events, ["watched", "playback_ended"])
})

test("pending HLS seeks and replaced sources exclude gaps while retaining observed time", () => {
  let now = 0
  const reports = [], video = new Video()
  const watched = createWatchedPlayback({video, clock: () => now, report: report => reports.push(report)})
  const config = {attemptId: "a", fileId: "7", playbackPhase: "ready"}
  Object.assign(video.dataset, config)
  watched.update(config)
  video.fileTimeline = {offset: 0, duration: 500}
  for (let i = 0; i <= 100; i++) { now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate")) }
  video.fileTimeline.pending = true
  for (let i = 101; i <= 450; i++) { now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate")) }
  assert.equal(reports.length, 0)
  watched.suspend()
  video.fileTimeline = {offset: 430, duration: 500}
  for (let i = 0; i <= 20; i++) { now++; video.currentTime = i; video.dispatchEvent(new Event("timeupdate")) }
  assert.equal(reports.length, 1)
  watched.destroy()
})
