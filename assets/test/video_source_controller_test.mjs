import test from "node:test"
import assert from "node:assert/strict"
import {createSourceController} from "../js/video/player/source_controller.mjs"

function setup() {
  const calls = []
  const video = {dataset: {}, pause() {}, load() {}, removeAttribute() {}}
  const el = {dataset: {fileId: "1", recoveryScope: "scope", videoId: "v1", src: "/direct"}}
  let allowed = true
  const recovery = {beforeSourceChange() {calls.push("checkpoint")}, source(options) {calls.push(options); return allowed}, ready() {calls.push("ready")}}
  const factory = type => ({video: element}) => {
    assert.equal(element, video)
    calls.push(type)
    return {update() {calls.push("update")}, destroy() {calls.push("destroy")}}
  }
  const source = createSourceController({el, video, recovery}, {direct: factory("direct"), hls: factory("hls")})
  return {source, el, video, calls, defer() {allowed = false}, allow() {allowed = true}}
}

test("same-signature updates retain the active controller and video", () => {
  const {source, el, video, calls} = setup()
  source.update()
  el.dataset.pausedServer = "true"
  source.update()
  assert.deepEqual(calls, ["checkpoint", {retry: false}, "direct", "update"])
  assert.equal(video.dataset.pausedServer, "true")
  source.destroy()
})

test("direct to HLS replacement retains video identity and disposes the outgoing source", () => {
  const {source, el, video, calls} = setup()
  source.update()
  Object.assign(el.dataset, {src: "/hls", sessionId: "hls", videoId: "v2"})
  source.update()
  assert.equal(video.id, "v2")
  assert.deepEqual(calls.slice(3), ["checkpoint", "destroy", {retry: false}, "hls"])
  delete el.dataset.sessionId
  el.dataset.src = "/direct-again"
  source.update()
  assert.equal(calls.at(-1), "direct")
  source.destroy()
})

test("visible errors stop the source and retry re-enters recovery", () => {
  const {source, el, calls} = setup()
  source.update()
  el.dataset.playbackError = "Unavailable"
  source.update()
  assert.deepEqual(calls.slice(3), ["checkpoint", "destroy"])
  delete el.dataset.playbackError
  source.update()
  assert.deepEqual(calls.slice(-3), ["checkpoint", {retry: true}, "direct"])
  source.destroy()
})

test("deferred recovery attaches only after explicit source retry", () => {
  const f = setup()
  f.defer()
  f.source.update()
  assert.equal(f.calls.includes("direct"), false)
  f.allow()
  f.source.retry()
  assert.equal(f.calls.at(-1), "direct")
  f.source.destroy()
})
