import test from "node:test"
import assert from "node:assert/strict"
import {parseFixture, renderPlaylist, publishedSegments, summarizePhase} from "../../scripts/playback/hls-measurement-helpers.mjs"

const fixture = () => parseFixture(`#EXTM3U
#EXT-X-TARGETDURATION:3
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:2.5,
first.ts
#EXTINF:1.5,
second.ts
#EXT-X-ENDLIST
`)

test("fixture metadata retains measured durations and rejects unsafe or unsupported inputs", () => {
  const parsed = fixture()
  assert.equal(parsed.targetDuration, 3)
  assert.deepEqual(parsed.segments, [{duration: 2.5, uri: "first.ts"}, {duration: 1.5, uri: "second.ts"}])
  for (const uri of ["../secret.ts", "https://example.test/private.ts", "first.ts?token=secret"]) {
    assert.throws(() => parseFixture(`#EXTM3U\n#EXT-X-TARGETDURATION:3\n#EXTINF:2,\n${uri}\n#EXT-X-ENDLIST`))
  }
  assert.throws(() => parseFixture("#EXTM3U\n#EXT-X-TARGETDURATION:3\n#EXTINF:NaN,\nfirst.ts\n#EXT-X-ENDLIST"))
  assert.throws(() => parseFixture("#EXTM3U\n#EXT-X-TARGETDURATION:3\n#EXT-X-KEY:METHOD=AES-128\n#EXTINF:2,\nfirst.ts\n#EXT-X-ENDLIST"))
})

test("publication follows actual durations and playlists slide with timestamp discontinuities", () => {
  const parsed = fixture()
  assert.equal(publishedSegments(parsed, 4), 2)
  assert.equal(publishedSegments(parsed, 6.49), 2)
  assert.equal(publishedSegments(parsed, 6.5), 3)
  const manifest = renderPlaylist(parsed, {published: 5, windowSize: 3})
  assert.match(manifest, /#EXT-X-MEDIA-SEQUENCE:2\n#EXT-X-DISCONTINUITY-SEQUENCE:1/)
  assert.match(manifest, /#EXTINF:1.5,\nseg-000003.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:2.5,\nseg-000004.ts/)
  assert.doesNotMatch(manifest, /ENDLIST|PLAYLIST-TYPE/)
  assert.match(renderPlaylist(parsed, {published: 2, completed: true}), /#EXT-X-ENDLIST\n$/)
})

test("phase accounting counts requests once and separates statuses, bytes and bootstrap", () => {
  const requests = [
    {phase: "bootstrap", resource: "manifest", at_ms: 0, status: 200, bytes: 10, latency_ms: 2},
    {phase: "paused", resource: "manifest", at_ms: 1000, status: 200, bytes: 20, latency_ms: 3, unchanged: false},
    {phase: "paused", resource: "manifest", at_ms: 3000, status: 200, bytes: 20, latency_ms: 5, unchanged: true},
    {phase: "paused", resource: "segment", at_ms: 3500, status: 200, bytes: 100, latency_ms: 4},
    {phase: "paused", resource: "manifest", at_ms: 4000, status: 404, bytes: 0, latency_ms: 1},
  ]
  const report = summarizePhase(requests, {name: "paused", duration_ms: 4000, position_start_s: 1, position_end_s: 1})
  assert.equal(report.resources.manifest.requests, 3)
  assert.deepEqual(report.resources.manifest.statuses, {200: 2, 404: 1})
  assert.equal(report.resources.manifest.bytes, 40)
  assert.deepEqual(report.resources.manifest.intervals_ms, [2000, 1000])
  assert.equal(report.resources.manifest.requests_per_minute, 45)
  assert.equal(report.resources.manifest.unchanged_fraction, 0.5)
  assert.equal(report.resources.segment.bytes, 100)
  assert.equal(report.position_advanced_s, 0)
  assert.equal(summarizePhase([], {name: "destroyed", duration_ms: 1000}).resources.manifest.latency_p95_ms, null)
})
