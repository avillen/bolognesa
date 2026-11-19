import test from "node:test"
import assert from "node:assert/strict"
import {createWatchedActivity} from "../js/video/player/watched_activity.mjs"

function fixture() {
  let now = 0
  const reports = []
  const activity = createWatchedActivity({clock: () => now, report: report => reports.push(report)})
  activity.select("attempt-1", "7")
  const update = (position, options = {}) => {
    now++
    activity.update({position, duration: 200, playing: true, ...options})
  }
  const play = (from, through, options = {}) => {
    for (let position = from; position <= through; position++) update(position, options)
  }
  return {activity, reports, update, play}
}

test("requires both 120 observed seconds and 90 percent and reports only once", () => {
  const f = fixture()
  f.play(0, 179)
  assert.equal(f.reports.length, 0)
  f.update(180)
  assert.deepEqual(f.reports, [{attempt_id: "attempt-1", file_id: "7"}])
  f.play(181, 200)
  assert.equal(f.reports.length, 1)
})

test("seeking to the end and abandoning early do not qualify", () => {
  const f = fixture()
  f.play(0, 30)
  f.update(190, {seeking: true})
  f.update(200, {ended: true, playing: false})
  assert.equal(f.reports.length, 0)
})

test("paused time and jumps do not count toward observed playback", () => {
  const f = fixture()
  f.play(0, 100)
  for (let i = 0; i < 120; i++) f.update(100, {playing: false})
  f.update(180)
  f.play(181, 190)
  assert.equal(f.reports.length, 0)
})

test("ended can qualify without a known duration after 120 seconds", () => {
  const f = fixture()
  f.play(0, 120, {duration: null})
  assert.equal(f.reports.length, 0)
  f.update(120, {duration: null, ended: true, playing: false})
  assert.equal(f.reports.length, 1)
})

test("same attempt survives stream replacement, new attempts reset observed time", () => {
  const f = fixture()
  f.play(0, 100)
  f.activity.select("attempt-1", "7")
  // A new HLS source already reports whole-file position; discontinuity is excluded.
  f.update(150, {seeking: true})
  f.play(150, 180)
  assert.equal(f.reports.length, 1)
  f.activity.select("attempt-2", "7")
  f.play(180, 200)
  assert.equal(f.reports.length, 1)
  f.activity.select("attempt-3", "8")
  f.play(0, 180)
  assert.equal(f.reports.length, 2)
})

test("preparation and source changes break sampling without resetting the attempt", () => {
  const f = fixture()
  f.play(0, 119)
  f.activity.suspend()
  f.update(180)
  assert.equal(f.reports.length, 0)
  f.update(181)
  assert.equal(f.reports.length, 1)
})

test("a failed acknowledgement allows only one retry after fifteen seconds in the same attempt", async () => {
  let now = 0, reports = 0
  const activity = createWatchedActivity({clock: () => now, report: () => {
    reports++
    return Promise.reject(new Error("server unavailable"))
  }})
  activity.select("attempt", "7")
  const sample = () => activity.update({position: now, duration: 200, playing: true})
  for (now = 0; now <= 180; now++) sample()
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(reports, 1)
  for (; now < 196; now++) sample()
  assert.equal(reports, 1)
  sample()
  assert.equal(reports, 2)
  await new Promise(resolve => setImmediate(resolve))
  for (; now <= 250; now++) sample()
  assert.equal(reports, 2)
})

test("a late failure from an old attempt cannot enable a retry on a new one", async () => {
  let now = 0, rejectOld, reports = 0
  const activity = createWatchedActivity({clock: () => now, report: () => {
    reports++
    return reports === 1 ? new Promise((_, reject) => { rejectOld = reject }) : Promise.resolve()
  }})
  const sample = () => activity.update({position: now, duration: 200, playing: true})
  activity.select("old", "7")
  for (now = 0; now <= 180; now++) sample()
  activity.select("new", "7")
  for (now = 0; now <= 180; now++) sample()
  assert.equal(reports, 2)
  rejectOld(new Error("late failure"))
  await new Promise(resolve => setImmediate(resolve))
  for (; now <= 220; now++) sample()
  assert.equal(reports, 2)
})
