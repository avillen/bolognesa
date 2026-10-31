import test from "node:test"
import assert from "node:assert/strict"
import {createMusicTransport} from "../js/music/music_transport.mjs"

test("transport posts authorized track selection with CSRF and same-origin credentials", async () => {
  let captured
  const transport = createMusicTransport({csrfToken: "csrf", fetch: async (...args) => {
    captured = args
    return {ok: true, redirected: false, status: 200, headers: {get: () => "application/json"}, json: async () => ({track: {id: 3, file_id: 8, title: "Track", state: "ready"}, src: "/music/tracks/3/media/8"})}
  }})
  await transport.selectTrack({trackId: 3, fileId: 8})
  assert.equal(captured[0], "/music/playback/track")
  assert.deepEqual(JSON.parse(captured[1].body), {track_id: 3, file_id: 8})
  assert.equal(captured[1].credentials, "same-origin")
  assert.equal(captured[1].headers["X-CSRF-Token"], "csrf")
})

test("transport maps authentication failures without parsing a redirect body", async () => {
  const transport = createMusicTransport({csrfToken: "csrf", fetch: async () => ({ok: false, redirected: true, status: 200})})
  await assert.rejects(transport.selectTrack({trackId: 3, fileId: 8}), error => error.code === "unauthenticated")
})
