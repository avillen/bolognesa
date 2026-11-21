import test from "node:test"
import assert from "node:assert/strict"
import {entryLinkId, restartThreshold} from "../js/video/player/ui/player_frame/page_hotkeys.mjs"

test("n always opens the next entry", () => {
  assert.equal(entryLinkId("n", 0), "episode-next")
  assert.equal(entryLinkId("n", 600), "episode-next")
})

test("p opens the previous entry only near the start; later it restarts", () => {
  assert.equal(entryLinkId("p", 0), "episode-previous")
  assert.equal(entryLinkId("p", restartThreshold - 0.1), "episode-previous")
  assert.equal(entryLinkId("p", restartThreshold), null)
})

test("other keys are left to Video.js", () => {
  assert.equal(entryLinkId("k", 0), null)
})
