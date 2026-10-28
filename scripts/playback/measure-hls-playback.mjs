// Synthetic transport baseline: production hook, controlled HTTP producer, no Phoenix/FFmpeg.
import assert from "node:assert/strict"
import {execFileSync} from "node:child_process"
import {createHash} from "node:crypto"
import {createServer} from "node:http"
import {mkdir, readFile, writeFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {performance} from "node:perf_hooks"
import {build} from "esbuild"
import {chromium} from "playwright"
import {parseFixture, publishedSegments, renderPlaylist, summarizePhase} from "./hls-measurement-helpers.mjs"

const args = process.argv.slice(2)
const directory = args.shift()
let seconds = 120, output = "tmp/hls-baseline/latest.json"
if (!directory || args.length % 2) throw new Error("Usage: node scripts/playback/measure-hls-playback.mjs FIXTURES [--phase-seconds 120] [--output tmp/hls-baseline/latest.json]")
for (let i = 0; i < args.length; i += 2) {
  if (args[i] === "--phase-seconds") seconds = Number(args[i + 1])
  else if (args[i] === "--output") output = args[i + 1]
  else throw new Error(`Unknown option: ${args[i]}`)
}
if (!Number.isFinite(seconds) || seconds < 2 || seconds > 600) throw new Error("Phase duration must be between 2 and 600 seconds")
const fixture = parseFixture(await readFile(resolve(directory, "index.m3u8"), "utf8"))
const segmentBodies = await Promise.all(fixture.segments.map(segment => readFile(resolve(directory, segment.uri))))
const config = await readFile("config/config.exs", "utf8")
const target = config.match(/--target=([^\s]+)/)[1].split(",")
const bundle = await build({stdin: {resolveDir: process.cwd(), contents: `
import hook from './assets/js/hooks/video_player.js';
window.hook = hook;
window.events = []; window.hlsErrors = [];
window.context = {el: document.querySelector('#frame'), pushEvent: (name, data, callback) => {
  window.events.push(name);
  window.playbackEvent(name, data).then(reply => {
    if (window.disposed) return;
    if (name === 'playback_pause' || name === 'playback_resume') {
      window.context.el.dataset.pausedServer = String(reply.paused);
      hook.updated.call(window.context);
    }
    callback?.(reply);
  });
}};
hook.mounted.call(window.context);
const hls = window.context.context?.hls;
if (hls) {
  window.hlsVersion = hls.constructor.version;
  hls.on(hls.constructor.Events.ERROR, (_event, data) => window.hlsErrors.push({
    type: data.type, details: data.details, fatal: data.fatal,
  }));
}
`}, bundle: true, write: false, target, format: "esm"})

const started = performance.now()
const states = new Map(["completed", "progressive", "initially-paused"].map(name => [name, {
  name, phase: "bootstrap", requests: [], phases: [], errors: [], expired: false,
  producerSeconds: 0, producerSince: null, previousManifest: null,
}]))
const setProducer = (state, playing) => {
  if (state.producerSince !== null) state.producerSeconds += (performance.now() - state.producerSince) / 1000
  state.producerSince = playing ? performance.now() : null
}
const available = state => 12 + state.producerSeconds + (state.producerSince === null ? 0 : (performance.now() - state.producerSince) / 1000)
assert.ok(publishedSegments(fixture, 12) > 0, "Fixture must publish at least one segment within the 12-second cushion")

const server = createServer(async (request, response) => {
  const [name, file] = new URL(request.url, "http://localhost").pathname.slice(1).split("/")
  const state = states.get(name)
  if (!state) return response.writeHead(404).end()
  try {
    if (!file) {
      response.setHeader("Content-Type", "text/html")
      return response.end(`<!DOCTYPE html><html><body>
<div id="frame" data-video-id="synthetic" data-file-id="1" data-session-id="synthetic"
data-offset-ms="0" data-duration-ms="86400000" data-autoplay="${name !== "initially-paused"}"
data-paused-server="true" data-src="/${name}/index.m3u8">
<video muted playsinline></video></div><script type="module" src="/${name}/player.js"></script></body></html>`)
    }
    if (file === "player.js") {
      response.setHeader("Content-Type", "text/javascript")
      return response.end(bundle.outputFiles[0].contents)
    }
    const sequence = /^seg-(\d{6,12})\.ts$/.exec(file)?.[1]
    if (file !== "index.m3u8" && sequence === undefined) return response.writeHead(404).end()
    const at = performance.now()
    const record = {phase: state.phase, resource: file === "index.m3u8" ? "manifest" : "segment",
      at_ms: at - started, status: "pending", bytes: 0, latency_ms: null}
    state.requests.push(record)
    response.on("finish", () => { record.status = response.statusCode; record.latency_ms = performance.now() - at })
    response.on("close", () => {
      if (record.status === "pending") { record.status = "aborted"; record.latency_ms = performance.now() - at }
    })
    response.setHeader("Cache-Control", "private, no-store")
    const published = name === "completed" ? fixture.segments.length : publishedSegments(fixture, available(state))
    let body
    if (state.expired || (sequence !== undefined && Number(sequence) >= published)) {
      response.statusCode = 404
      body = Buffer.alloc(0)
    } else if (file === "index.m3u8") {
      const manifest = renderPlaylist(fixture, {published, windowSize: name === "completed" ? published : 12, completed: name === "completed"})
      if (state.previousManifest !== null) record.unchanged = state.previousManifest === manifest
      state.previousManifest = manifest
      record.playlist = {target_duration_s: fixture.targetDuration, media_sequence: Math.max(0, published - (name === "completed" ? published : 12)),
        endlist: name === "completed", extinf_s: [...manifest.matchAll(/#EXTINF:([\d.]+),/g)].map(match => Number(match[1]))}
      response.setHeader("Content-Type", "application/vnd.apple.mpegurl")
      body = Buffer.from(manifest)
    } else {
      response.setHeader("Content-Type", "video/mp2t")
      body = segmentBodies[Number(sequence) % segmentBodies.length]
    }
    record.bytes = body.length
    response.end(body)
  } catch {
    response.writeHead(500).end()
  }
})

let browser
try {
  await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve) })
  // Verify accounting against real HTTP responses before involving a player.
  const control = states.get("completed")
  for (const file of ["index.m3u8", "seg-000000.ts", "index.m3u8"]) {
    control.expired = control.requests.length === 2
    await (await fetch(`http://127.0.0.1:${server.address().port}/completed/${file}`)).arrayBuffer()
  }
  assert.deepEqual(control.requests.map(({resource, status}) => [resource, status]), [["manifest", 200], ["segment", 200], ["manifest", 404]])
  assert.equal(control.requests[1].bytes, segmentBodies[0].length)
  control.requests = []; control.expired = false; control.previousManifest = null
  browser = process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS
    ? await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, {exposeNetwork: "<loopback>"})
    : await chromium.launch({headless: true, channel: process.env.BOLOGNESA_TEST_BROWSER_CHANNEL})
  const run = async state => {
    const page = await browser.newPage()
    page.on("pageerror", error => state.errors.push({phase: state.phase, name: error.name, message: error.message}))
    await page.exposeFunction("playbackEvent", (name, data) => {
      if (data?.session_id === "synthetic" && ["playback_pause", "playback_resume"].includes(name)) setProducer(state, name === "playback_resume")
      return {paused: state.producerSince === null}
    })
    const position = () => page.evaluate(() => document.querySelector("video").currentTime)
    const phase = async (name, action, duration = seconds) => {
      state.phase = name
      const start = performance.now(), position_start_s = await position()
      await action?.()
      await page.waitForTimeout(duration * 1000)
      const position_end_s = await position()
      state.phases.push({name, duration_ms: performance.now() - start, position_start_s, position_end_s})
      console.error(`${state.name}: ${name} measured (${duration}s requested)`)
    }
    const boot = performance.now()
    await page.goto(`http://127.0.0.1:${server.address().port}/${state.name}/`)
    await page.waitForFunction(() => document.querySelector("video").readyState >= 2 && window.hlsVersion, null, {timeout: 15000})
    if (state.name !== "initially-paused") await page.waitForFunction(() => document.querySelector("video").currentTime > 0.1)
    state.hlsVersion = await page.evaluate(() => window.hlsVersion)
    state.phases.push({name: "bootstrap", duration_ms: performance.now() - boot, position_start_s: 0, position_end_s: await position()})
    if (state.name === "completed") {
      await phase("completed")
    } else if (state.name === "progressive") {
      await phase("playing")
      await phase("paused", () => page.evaluate(() => document.querySelector("video").pause()))
      await phase("resumed", () => page.evaluate(() => document.querySelector("video").play()))
    } else {
      await phase("initially-paused")
      await phase("expired", () => { state.expired = true })
    }
    // Start the observation boundary after teardown has completed, not before its RPC.
    await page.evaluate(() => { window.disposed = true; window.hook.destroyed.call(window.context) })
    await phase("destroyed")
    state.browserEvents = await page.evaluate(() => window.events.reduce((counts, name) => { counts[name] = (counts[name] || 0) + 1; return counts }, {}))
    state.hlsErrors = await page.evaluate(() => window.hlsErrors)
    await page.close()
  }
  const outcomes = await Promise.allSettled([...states.values()].map(run))
  const report = {
    schema_version: 1, origin: "synthetic-production-hook", phase_seconds_requested: seconds,
    cadence_baseline: false, validation_passed: false,
    commit: execFileSync("git", ["rev-parse", "HEAD"], {encoding: "utf8"}).trim(),
    working_tree_dirty: execFileSync("git", ["status", "--porcelain"], {encoding: "utf8"}).trim().length > 0,
    hook_bundle_sha256: createHash("sha256").update(bundle.outputFiles[0].contents).digest("hex"), counter_self_check: "passed",
    browser: browser.version(), fixture: {target_duration_s: fixture.targetDuration, extinf_s: fixture.segments.map(segment => segment.duration),
      duration_s: fixture.duration, segment_count: fixture.segments.length},
    limits: ["No Phoenix, database, FFmpeg or NAS measurements", "Synthetic producer pauses on hook events; no automatic five-minute expiry",
      "Short fixture cycles have explicit timestamp discontinuities; this is not an encoding benchmark",
      "Bytes are response body sizes handed to the HTTP server, not network-interface traffic",
      "Phase attribution uses request arrival, including requests whose response finishes later"],
    scenarios: [...states.values()].map(state => ({name: state.name, hls_version: state.hlsVersion,
      phases: state.phases.map(phase => summarizePhase(state.requests, phase)), requests: state.requests,
      browser_errors: state.errors, browser_events: state.browserEvents, hls_errors: state.hlsErrors})),
    failures: outcomes.flatMap((outcome, index) => outcome.status === "rejected" ? [{scenario: [...states.keys()][index], message: outcome.reason.message}] : []),
  }
  await mkdir(dirname(output), {recursive: true})
  await writeFile(output, JSON.stringify(report, null, 2) + "\n")
  assert.deepEqual(report.failures, [], "Measurement scenario failed; inspect report")
  for (const scenario of report.scenarios) {
    assert.deepEqual(scenario.browser_errors, [], `${scenario.name}: browser exception`)
    const destroyed = scenario.phases.find(phase => phase.name === "destroyed")
    assert.equal(destroyed.resources.manifest.requests + destroyed.resources.segment.requests, 0, `${scenario.name}: requests after teardown`)
  }
  const completed = report.scenarios.find(scenario => scenario.name === "completed").requests.filter(request => request.resource === "manifest")
  assert.ok(completed.length <= 2, "Completed playlist keeps reloading")
  const progressive = report.scenarios.find(scenario => scenario.name === "progressive")
  for (const name of ["playing", "resumed"]) {
    assert.ok(progressive.phases.find(phase => phase.name === name).position_advanced_s > seconds * 0.5, `${name}: synthetic playback did not advance`)
  }
  // Paused request counts are observations, not assertions that lock in the existing bug.
  report.validation_passed = true
  report.cadence_baseline = seconds >= 120
  await writeFile(output, JSON.stringify(report, null, 2) + "\n")
  console.log(`Validated synthetic HLS report: ${output}`)
} finally {
  await browser?.close()
  server.closeAllConnections()
  await new Promise(resolve => server.close(resolve))
}
