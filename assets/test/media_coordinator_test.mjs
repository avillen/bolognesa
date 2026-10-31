import test from "node:test"
import assert from "node:assert/strict"
import {createMediaCoordinator} from "../js/music/music_bootstrap/media_coordinator.mjs"

class Media extends EventTarget {
  constructor() { super(); this.paused = true; this.pauses = 0 }
  pause() { this.pauses++; this.paused = true; this.dispatchEvent(new Event("pause")) }
  start() { this.paused = false; this.dispatchEvent(new Event("playing")) }
}

test("playing media pauses the other active element without automatic resumption", () => {
  const coordinator = createMediaCoordinator()
  const music = new Media(), video = new Media()
  const unregisterMusic = coordinator.register(music)
  const unregisterVideo = coordinator.register(video)
  music.start()
  video.start()
  assert.equal(music.paused, true)
  assert.equal(video.paused, false)
  assert.equal(video.pauses, 0)
  music.start()
  assert.equal(video.paused, true)
  assert.equal(music.paused, false)
  unregisterMusic(); unregisterVideo()
})

test("repeated playing events and unregistered media do not pause another element", () => {
  const coordinator = createMediaCoordinator()
  const music = new Media(), video = new Media()
  coordinator.register(music)
  const unregister = coordinator.register(video)
  video.start(); music.start(); music.start()
  assert.equal(video.pauses, 1)
  unregister()
  video.paused = false
  music.start()
  assert.equal(video.pauses, 1)
})
