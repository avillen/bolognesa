import test from "node:test"
import assert from "node:assert/strict"
import {createListeningActivity} from "../js/music/music_bootstrap/session/listening_activity.mjs"

test("counts playback time, excluding pauses and seeks, once per selection", () => {
  let now = 0
  const reports = []
  const activity = createListeningActivity({clock: () => now, report: track => reports.push(track)})
  activity.select({id: 1, file_id: 2}, 100)
  activity.update({position: 0, playing: true})
  now += 10; activity.update({position: 10, playing: true})
  now += 1; activity.update({position: 80, playing: true, seeking: true})
  now += 100; activity.update({position: 80, playing: false})
  now += 1; activity.update({position: 80, playing: true})
  now += 19; activity.update({position: 99, playing: true})
  assert.equal(reports.length, 0)
  now += 1; activity.update({position: 100, playing: true})
  assert.deepEqual(reports, [{id: 1, file_id: 2}])
  now += 10; activity.update({position: 100, playing: true})
  assert.equal(reports.length, 1)
})

test("short tracks qualify after half their duration", () => {
  let now = 0
  let reports = 0
  const activity = createListeningActivity({clock: () => now, report: () => reports++})
  activity.select({id: 1, file_id: 2}, 10)
  activity.update({position: 0, playing: true})
  now = 4; activity.update({position: 4, playing: true})
  assert.equal(reports, 0)
  now = 5; activity.update({position: 5, playing: true})
  assert.equal(reports, 1)
})

test("retries a failed report while playback continues", async () => {
  let now = 0, attempts = 0
  const activity = createListeningActivity({clock: () => now, report: async () => {
    attempts++
    if (attempts === 1) throw new Error("offline")
  }})
  activity.select({id: 1, file_id: 2}, 10)
  activity.update({position: 0, playing: true})
  now = 5; activity.update({position: 5, playing: true})
  await new Promise(resolve => setImmediate(resolve))
  now = 21; activity.update({position: 6, playing: true})
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(attempts, 2)
})
