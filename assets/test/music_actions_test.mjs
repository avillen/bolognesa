import test from "node:test"
import assert from "node:assert/strict"
import {parseMusicAction, executeMusicAction} from "../js/music/hooks/audio_player/actions.mjs"

const command = dataset => parseMusicAction({dataset})
test("recent album continuation always selects the saved track with strict matching", () => {
  const calls = []
  const session = {playAlbum: value => calls.push(value)}
  const action = command({musicAction: "resume-album", albumId: "4", libraryId: "3", trackId: "2", fileId: "12"})
  assert.ok(action)
  executeMusicAction(session, action)
  assert.deepEqual(calls, [{albumId: 4, libraryId: 3, trackId: 2, fileId: 12, requireTrack: true}])
  assert.equal(command({musicAction: "resume-album", albumId: "4"}), null)
})
test("screen commands reject invalid identifiers and unknown actions", () => {
  for (const trackId of ["", "-1", "1.5", "1e2", "9007199254740992"]) {
    assert.equal(command({musicAction: "track", trackId, fileId: "2"}), null)
  }
  assert.equal(command({musicAction: "unknown"}), null)
  assert.equal(command({musicAction: "album", albumId: "1", libraryId: "bad"}), null)
})

test("track-only ignores album context while album-track preserves it", () => {
  const dataset = {trackId: "2", fileId: "12", albumId: "4", libraryId: "3"}
  const calls = []
  const session = {getSnapshot: () => ({selected: null}), selectTrack: x => calls.push(["track", x]), playAlbum: x => calls.push(["album", x])}
  executeMusicAction(session, command({...dataset, musicAction: "track-only"}))
  executeMusicAction(session, command({...dataset, musicAction: "album-track"}))
  assert.deepEqual(calls, [["track", {trackId: 2, fileId: 12}], ["album", {albumId: 4, libraryId: 3, trackId: 2, fileId: 12}]])
})

test("selecting the active track toggles its current pause state", () => {
  const calls = []
  const snapshot = {selected: {id: 2, file_id: 12}, paused: true}
  const session = {getSnapshot: () => snapshot, play: () => calls.push("play"), pause: () => calls.push("pause")}
  const action = command({musicAction: "track", trackId: "2", fileId: "12"})
  executeMusicAction(session, action)
  snapshot.paused = false
  executeMusicAction(session, action)
  assert.deepEqual(calls, ["play", "pause"])
})
