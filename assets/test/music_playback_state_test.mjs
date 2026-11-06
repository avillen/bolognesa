import test from "node:test"
import assert from "node:assert/strict"
import {createPlaybackState, selectionStarted, selectionAccepted, selectionFailed} from "../js/music/player/model/playback_state.mjs"
import {albumTracksFrom, isReadyTrack} from "../js/music/player/model/selection.mjs"

test("starting selection retains the outgoing track and clears the previous failure", () => {
  const previous = Object.freeze({selected: {id: 1}, loading: false, finished: true, error: {code: "unavailable"}})
  assert.deepEqual(selectionStarted(previous), {selected: {id: 1}, loading: true, finished: true, error: null})
  assert.equal(previous.loading, false)
  assert.equal(previous.error.code, "unavailable")
})

test("authorized selection starts a fresh playback state without retaining mutable track input", () => {
  const previous = Object.freeze({...createPlaybackState(), finished: true, loading: true, error: {code: "unavailable"}})
  const track = {id: 2, file_id: 12}
  const selected = selectionAccepted(previous, track)
  track.id = 3
  assert.deepEqual(selected, {selected: {id: 2, file_id: 12}, loading: false, finished: false, error: null})
  assert.equal(previous.selected, null)
  assert.equal(previous.finished, true)
})

test("selection failure preserves outgoing playback and exposes a retryable reason", () => {
  const previous = Object.freeze({selected: {id: 1}, loading: true, finished: false, error: null})
  assert.deepEqual(selectionFailed(previous, "forbidden"), {selected: {id: 1}, loading: false, finished: false, error: {code: "forbidden", retryable: true}})
  assert.equal(previous.loading, true)
})

test("an explicit album index takes precedence over a requested track", () => {
  const tracks = [{id: 1, file_id: 11}, {id: 2, file_id: 12}, {id: 3, file_id: 13}]
  assert.deepEqual(albumTracksFrom(tracks, {trackId: 1, startIndex: 1}), tracks.slice(1))
  assert.equal(tracks.length, 3)
})

test("album selection distinguishes files and falls back to the beginning for unknown positions", () => {
  const tracks = [{id: 1, file_id: 11}, {id: 1, file_id: 12}, {id: 2, file_id: 13}]
  assert.deepEqual(albumTracksFrom(tracks, {trackId: 1, fileId: 12}), tracks.slice(1))
  assert.deepEqual(albumTracksFrom(tracks, {trackId: 8, startIndex: -1}), tracks)
  assert.deepEqual(albumTracksFrom(tracks, {startIndex: 8}), tracks)
  assert.deepEqual(albumTracksFrom([], {}), [])
})

test("only identified ready tracks can be selected from a queue", () => {
  assert.equal(isReadyTrack({id: 1, file_id: 11, state: "ready"}), true)
  for (const track of [null, {id: 1, file_id: 11, state: "missing"}, {id: null, file_id: 11, state: "ready"}, {id: 1, file_id: null, state: "ready"}]) {
    assert.equal(isReadyTrack(track), false)
  }
})
