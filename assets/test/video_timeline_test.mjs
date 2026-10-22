import test from "node:test"
import assert from "node:assert/strict"
import {fileTimeFeature, fileBufferFeature} from "../js/video_timeline.mjs"

// The native feature boundary supplies browser time; our adapter must publish file time.
const nativeTime = {
  name: "time",
  state: () => ({seek: async time => time}),
  attach({set}) { set({currentTime: 12, duration: Infinity, seeking: false}) },
}
const nativeBuffer = {
  name: "buffer",
  attach({set}) { set({buffered: [[0, 15]], seekable: [[0, 20]]}) },
}

test("transcode controls expose file time and seek through the server", async () => {
  const seeks = []
  const media = {fileTimeline: {offset: 120, duration: 600, seek: time => seeks.push(time)}}
  let state
  const context = {target: () => ({media}), set: value => { state = value }}
  const feature = fileTimeFeature(nativeTime)
  feature.attach({...context, target: {media}})
  assert.deepEqual(state, {currentTime: 132, duration: 600, seeking: false})
  await feature.state(context).seek(400)
  assert.deepEqual(seeks, [400])
  assert.equal(state.currentTime, 400)
  assert.equal(state.seeking, true)
})

test("direct playback retains native time and seek behavior", async () => {
  let state
  const context = {target: () => ({media: {}}), set: value => { state = value }}
  const feature = fileTimeFeature(nativeTime)
  feature.attach({...context, target: {media: {}}})
  assert.equal(state.currentTime, 12)
  assert.equal(await feature.state(context).seek(25), 25)
})

test("buffered fragments use the file offset but the whole file remains seekable", () => {
  let state
  fileBufferFeature(nativeBuffer).attach({
    target: {media: {fileTimeline: {offset: 120, duration: 600}}},
    set: value => { state = value },
  })
  assert.deepEqual(state, {buffered: [[120, 135]], seekable: [[0, 600]]})
})

test("unknown duration stays unknown and invalid seeks do not reach the server", async () => {
  const seeks = []
  const media = {fileTimeline: {offset: 120, duration: 0, seek: time => seeks.push(time)}}
  let state
  const context = {target: () => ({media}), set: value => { state = value }}
  const feature = fileTimeFeature(nativeTime)
  feature.attach({...context, target: {media}})
  assert.equal(state.duration, 0)
  await feature.state(context).seek(NaN)
  assert.deepEqual(seeks, [])
})
