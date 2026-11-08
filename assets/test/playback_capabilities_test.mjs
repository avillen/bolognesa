import {test} from "node:test"
import assert from "node:assert/strict"
import {probePlaybackCapabilities} from "../js/video/player/playback_capabilities.mjs"

const configuration = {mime: "video/mp4", video: {codec_string: "avc1.42C029", width: 320, height: 180, frame_rate: 24, bit_rate: 800000}, audio: null}
const candidate = {id: "c0", transports: ["file"], configuration}
const probe = (overrides = {}, candidates = [candidate]) => probePlaybackCapabilities({generation: "g1", candidates}, {video: {canPlayType: () => "probably"}, ...overrides})
test("uses exact codecs and preserves positive element evidence without Media Capabilities", async () => {
  const queried = []
  const report = await probe({video: {canPlayType: mime => { queried.push(mime); return "probably" }}})
  assert.deepEqual(queried, ['video/mp4; codecs="avc1.42C029"'])
  assert.equal(report.results[0].support, "supported")
  assert.equal(report.version, 1)
  assert.equal(report.generation, "g1")
})
test("maybe is unknown and explicit Media Capabilities rejection wins", async () => {
  assert.equal((await probe({video: {canPlayType: () => "maybe"}})).results[0].support, "unknown")
  assert.equal((await probe({mediaCapabilities: {decodingInfo: async () => ({supported: false})}})).results[0].support, "unsupported")
  assert.equal((await probe({mediaCapabilities: {decodingInfo: async () => { throw Error("unavailable") }}})).results[0].support, "supported")
})
test("omits incomplete decoding configurations instead of inventing zero dimensions", async () => {
  let calls = 0
  const incomplete = {...candidate, configuration: {...configuration, video: {...configuration.video, width: null}}}
  const report = await probe({mediaCapabilities: {decodingInfo: async () => { calls++; return {supported: true} }}}, [incomplete])
  assert.equal(calls, 0)
  assert.equal(report.results[0].support, "supported")
})
test("one aggregate deadline returns unknown for unfinished probes", async () => {
  const report = await probe({deadlineMs: 5, mediaCapabilities: {decodingInfo: () => new Promise(() => {})}})
  assert.equal(report.results[0].support, "unknown")
})
test("HLS.js requires HLS and exact MSE codecs, native HLS requires both MIME and streams", async () => {
  const hls = {...candidate, transports: ["hls_js", "native_hls"]}
  const options = {Hls: {isSupported: () => true}, MediaSource: {isTypeSupported: () => true}}
  assert.equal((await probe(options, [hls])).results[0].transport, "hls_js")
  assert.equal((await probe({...options, MediaSource: {isTypeSupported: () => false}}, [hls])).results[0].transport, "native_hls")
  const report = await probe({...options, video: {canPlayType: mime => mime.includes("mpegurl") ? "probably" : ""}, MediaSource: {isTypeSupported: () => false}}, [hls])
  assert.equal(report.results[0].support, "unsupported")
})

test("native HLS recognition can be maybe while exact elementary streams must be positive", async () => {
  const hls = {...candidate, transports: ["hls_js", "native_hls"]}
  const options = {Hls: {isSupported: () => false}, MediaSource: undefined,
    video: {canPlayType: mime => mime === "application/vnd.apple.mpegurl" ? "maybe" : "probably"}}
  const result = (await probe(options, [hls])).results[0]
  assert.equal(result.transport, "native_hls")
  assert.equal(result.support, "supported")
  for (const streams of ["maybe", ""]) {
    const report = await probe({...options, video: {canPlayType: mime => mime.includes("mpegurl") ? "maybe" : streams}}, [hls])
    assert.equal(report.results[0].support, streams === "" ? "unsupported" : "unknown")
  }
  const absent = await probe({...options, video: {canPlayType: mime => mime.includes("mpegurl") ? "" : "probably"}}, [hls])
  assert.equal(absent.results[0].support, "unsupported")
  const rejected = await probe({...options, mediaCapabilities: {decodingInfo: async () => ({supported: false})}}, [hls])
  assert.equal(rejected.results[0].support, "unsupported")
  const throwing = await probe({...options, video: {canPlayType: mime => {
    if (mime.includes("mpegurl")) throw Error("unavailable")
    return "probably"
  }}}, [hls])
  assert.equal(throwing.results[0].support, "unknown")
})
