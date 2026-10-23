// Run with a directory containing synthetic sample.mp4 and index.m3u8 + its segments.
// The browser loads the production hook and Video.js bundle; server events are captured at the LiveView boundary.
import assert from "node:assert/strict"
import {createServer} from "node:http"
import {mkdtemp, readFile, rm} from "node:fs/promises"
import {tmpdir} from "node:os"
import {join, resolve} from "node:path"
import {build} from "esbuild"
import {chromium} from "playwright"

const mediaDirectory = process.argv[2]
if (!mediaDirectory) throw new Error("Pass a directory with synthetic sample.mp4 and HLS index.m3u8 fixtures.")
const temporary = await mkdtemp(join(tmpdir(), "bolognesa-player-"))
const bundle = join(temporary, "player.js")
await build({stdin: {contents: `import hook from './assets/js/hooks/video_player.js';
window.events = [];
window.context = {el: document.querySelector('#frame'), pushEvent: (...event) => window.events.push(event)};
window.hook = hook;
hook.mounted.call(window.context);`, resolveDir: process.cwd()}, bundle: true, format: "esm", outfile: bundle})
const playerStyles = (await readFile("assets/css/app.css", "utf8")).split("/* Video.js owns")[1]
const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>/* Video.js owns${playerStyles}</style></head><body>
<div id="frame" data-video-id="video-1" data-file-id="1" data-src="/sample.mp4" data-autoplay="true" data-paused-server="false" class="bolognesa-video-frame" style="width:800px">
<media-i18n lang="en"><video muted playsinline style="width:100%;aspect-ratio:16/9"></video></media-i18n>
</div><script type="module" src="/player.js"></script></body></html>`
const server = createServer(async (request, response) => {
  try {
    const name = new URL(request.url, "http://localhost").pathname.slice(1)
    const files = {"player.js": bundle, "images/bolognesa-cat.svg": resolve("priv/static/images/bolognesa-cat.svg")}
    const path = files[name] ?? resolve(mediaDirectory, name)
    if (name && !files[name] && !/^(sample\.mp4|index\.m3u8|segment\d+\.ts)$/.test(name)) {
      response.writeHead(404).end()
      return
    }
    const types = {svg: "image/svg+xml", js: "text/javascript", mp4: "video/mp4", m3u8: "application/vnd.apple.mpegurl", ts: "video/mp2t"}
    const content = name ? await readFile(path) : Buffer.from(html)
    const headers = {"Content-Type": types[name.split(".").pop()] ?? "text/html", "Accept-Ranges": "bytes"}
    const range = /^bytes=(\d+)-(\d*)$/.exec(request.headers.range || "")
    if (range) {
      const start = Number(range[1]), end = range[2] ? Number(range[2]) : content.length - 1
      const body = content.subarray(start, end + 1)
      response.writeHead(206, {...headers, "Content-Length": body.length, "Content-Range": `bytes ${start}-${end}/${content.length}`})
      response.end(body)
    } else {
      response.writeHead(200, {...headers, "Content-Length": content.length})
      response.end(content)
    }
  } catch { response.writeHead(404).end() }
})
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
const browser = process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS
  ? await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, {exposeNetwork: "<loopback>"})
  : await chromium.launch({headless: true, channel: process.env.BOLOGNESA_TEST_BROWSER_CHANNEL})
try {
  const legacyPage = await browser.newPage({viewport: {width: 1000, height: 800}})
  legacyPage.setDefaultTimeout(15000)
  const legacyErrors = []
  legacyPage.on("pageerror", error => legacyErrors.push(error.message))
  await legacyPage.addInitScript(() => {
    const NativeNumberFormat = Intl.NumberFormat
    Intl.NumberFormat = class extends NativeNumberFormat {
      constructor(locale, options) {
        if (options?.style === "unit") throw new RangeError("Unit formatting is unsupported")
        super(locale, options)
      }
    }
  })
  await legacyPage.goto(`http://127.0.0.1:${server.address().port}`)
  await legacyPage.waitForFunction(() => document.querySelector("video").currentTime > 0.1)
  assert.deepEqual(legacyErrors, [], "Timeline must work without Intl unit formatting")
  await legacyPage.locator("video").hover()
  await legacyPage.locator("media-play-button").click()
  await legacyPage.waitForFunction(() => document.querySelector("video").paused)
  const legacySlider = legacyPage.locator("media-time-slider")
  const legacyTrack = await legacySlider.locator("media-slider-track").boundingBox()
  assert.ok(legacyTrack && legacyTrack.width > 100 && legacyTrack.height > 0)
  const times = await legacyPage.locator("media-time").allTextContents()
  assert.ok(times.length === 2 && times.every(time => /\d+:\d{2}/.test(time)))
  await legacySlider.focus()
  await legacyPage.keyboard.press("ArrowRight")
  await legacyPage.waitForFunction(() => document.querySelector("video").currentTime > 1)
  await legacyPage.locator("media-i18n").evaluate(element => { element.lang = "es" })
  await legacyPage.waitForFunction(() => document.querySelector("video-skin").shadowRoot.querySelector("media-time").getAttribute("aria-label")?.includes("Tiempo reproducido"))
  await legacyPage.evaluate(() => {
    Object.assign(window.context.el.dataset, {videoId: "legacy-hls", sessionId: "legacy", src: "/index.m3u8", offsetMs: "120000", durationMs: "600000"})
    window.hook.updated.call(window.context)
  })
  await legacyPage.waitForFunction(() => document.querySelector("bolognesa-video-player").store.state.duration === 600)
  await legacySlider.focus()
  await legacyPage.keyboard.press("ArrowRight")
  await legacyPage.waitForFunction(() => window.events.some(([name, data]) => name === "playback_seek" && data.session_id === "legacy"))
  assert.deepEqual(legacyErrors, [])
  await legacyPage.evaluate(() => window.hook.destroyed.call(window.context))
  await legacyPage.close()
  console.log("Compatibility: timeline, English/Spanish time labels and seeking without Intl unit formatting passed.")
  const page = await browser.newPage({viewport: {width: 1000, height: 800}})
  const errors = []
  page.on("pageerror", error => { errors.push(error.message); console.error(error.stack) })
  let releaseInitialLoad
  const initialLoad = new Promise(resolve => { releaseInitialLoad = resolve })
  await page.route("**/sample.mp4", async route => {
    await initialLoad
    await route.continue()
  })
  await page.goto(`http://127.0.0.1:${server.address().port}`, {waitUntil: "domcontentloaded"})
  await page.waitForFunction(() => !!window.context?.sync)
  assert.equal(await page.locator("video-skin").getAttribute("data-initial-loading"), "")
  assert.match(await page.locator("video-skin").evaluate(skin => getComputedStyle(skin, "::after").backgroundImage), /images\/bolognesa-cat.svg/)
  assert.equal(await page.locator("video-skin").evaluate(skin => getComputedStyle(skin, "::after").backgroundColor), "rgb(194, 110, 84)")
  if (process.env.BOLOGNESA_OPENING_SCREENSHOT) {
    await page.screenshot({path: process.env.BOLOGNESA_OPENING_SCREENSHOT})
  }
  releaseInitialLoad()
  await page.waitForFunction(() => document.querySelector("video").currentTime > 0.1).catch(async error => {
    console.error(await page.evaluate(() => ({
      video: {
        error: document.querySelector("video").error?.message,
        src: document.querySelector("video").src,
        ready: document.querySelector("video").readyState,
      },
      events: window.events,
    })))
    throw error
  })
  assert.equal(await page.locator("video-skin").getAttribute("data-initial-loading"), null)
  await page.locator("video").evaluate(video => video.dispatchEvent(new Event("waiting")))
  assert.equal(await page.locator("video-skin").getAttribute("data-initial-loading"), null)
  assert.equal(await page.locator("media-time-slider").count(), 1)
  assert.equal(await page.locator("video").evaluate(video => video.controls), false)
  await page.locator("video").hover()
  await page.locator("media-play-button").click()
  await page.waitForFunction(() => document.querySelector("video").paused)
  const slider = page.locator("media-time-slider")
  assert.equal(await slider.locator("media-slider-track").count(), 1)
  if (process.env.BOLOGNESA_PLAYER_SCREENSHOT) await page.screenshot({path: process.env.BOLOGNESA_PLAYER_SCREENSHOT})
  await slider.focus()
  await page.keyboard.press("ArrowRight")
  await page.waitForFunction(() => document.querySelector("video").currentTime > 1)
  assert.deepEqual(await page.evaluate(() => window.events.filter(([name]) => name !== "playback_diagnostic")), [])
  const mounted = await page.evaluate(() => window.events.find(([name, data]) => name === "playback_diagnostic" && data.diagnostic === "mounted"))
  assert.equal(mounted[1].file_id, "1")
  assert.match(mounted[1].tab_id, /^[0-9a-f-]{36}$/)
  await page.evaluate(() => {
    window.hook.disconnected.call(window.context)
    window.hook.reconnected.call(window.context)
  })
  const connectionEvents = await page.evaluate(() => window.events
    .filter(([name, data]) => name === "playback_diagnostic" && ["mounted", "disconnected", "reconnected"].includes(data.diagnostic)).map(([, data]) => data.diagnostic))
  assert.deepEqual(connectionEvents, ["mounted", "disconnected", "reconnected"])
  console.log("Direct: Video.js play/pause and keyboard seeking passed.")

  await page.evaluate(() => {
    Object.assign(window.context.el.dataset, {videoId: "video-a", sessionId: "a", src: "/index.m3u8", offsetMs: "120000", durationMs: "600000"})
    window.hook.updated.call(window.context)
  })
  await page.waitForFunction(() => document.querySelector("video").currentTime > 0.1)
  const readTime = () => page.evaluate(() => document.querySelector("bolognesa-video-player").store.state)
  assert.equal((await readTime()).duration, 600)
  assert.ok((await readTime()).currentTime >= 120)
  await slider.focus()
  await page.keyboard.press("ArrowRight")
  await page.waitForFunction(() => window.events.some(([name]) => name === "playback_seek"))
  let events = await page.evaluate(() => window.events)
  let seeks = events.filter(([name]) => name === "playback_seek")
  assert.equal(seeks.length, 1)
  assert.equal(seeks[0][1].session_id, "a")
  assert.ok(Number(seeks[0][1].position_ms) > 120000)
  assert.equal(seeks[0][1].playing, "true")
  console.log("HLS: full-file duration/offset and keyboard seek emit one server request.")

  // The server replaces the FFmpeg session. The container and fullscreen must survive.
  await page.locator("video").hover()
  await page.locator("media-fullscreen-button").click()
  await page.waitForFunction(() => document.fullscreenElement)
  await page.evaluate(() => {
    window.originalPlayer = document.querySelector("bolognesa-video-player")
    Object.assign(window.context.el.dataset, {videoId: "video-b", sessionId: "b", src: "/index.m3u8?session=b", offsetMs: "400000"})
    window.hook.updated.call(window.context)
  })
  await page.waitForFunction(() => document.querySelector("video").currentTime > 0.1 && document.querySelector("video").id === "video-b")
  assert.equal(await page.evaluate(() => window.originalPlayer === document.querySelector("bolognesa-video-player") && !!document.fullscreenElement), true)
  assert.ok((await readTime()).currentTime >= 400)
  await page.locator("video").hover()
  await page.locator("media-play-button").click()
  await page.waitForFunction(() => window.events.some(([name, data]) => name === "playback_pause" && data.session_id === "b"))
  await page.evaluate(() => {
    window.context.el.dataset.pausedServer = "true"
    window.hook.updated.call(window.context)
  })
  await page.locator("video").hover()
  await page.locator("media-play-button").click()
  await page.waitForFunction(() => window.events.some(([name, data]) => name === "playback_resume" && data.session_id === "b"))
  events = await page.evaluate(() => window.events)
  assert.ok(Number(events.find(([name]) => name === "playback_resume")[1].position_ms) >= 400000)
  console.log("HLS: session replacement preserves fullscreen; pause/resume uses file time.")
  // Drag outside the generated 400–420 second fragment while paused.
  await page.evaluate(() => {
    window.context.el.dataset.pausedServer = "false"
    window.hook.updated.call(window.context)
  })
  await page.locator("video").hover()
  await page.locator("media-play-button").click()
  await page.waitForFunction(() => document.querySelector("video").paused)
  await page.evaluate(() => {
    window.context.el.dataset.pausedServer = "true"
    window.hook.updated.call(window.context)
  })
  const bounds = await slider.boundingBox()
  await page.mouse.move(bounds.x + bounds.width * 0.2, bounds.y + bounds.height / 2)
  await page.mouse.down()
  await page.mouse.move(bounds.x + bounds.width * 0.75, bounds.y + bounds.height / 2, {steps: 4})
  assert.equal(await page.evaluate(() => window.events.filter(([name]) => name === "playback_seek").length), 1)
  await page.mouse.up()
  await page.waitForFunction(() => window.events.filter(([name]) => name === "playback_seek").length === 2)
  seeks = await page.evaluate(() => window.events.filter(([name]) => name === "playback_seek"))
  const lastSeek = seeks[1][1]
  assert.ok(Number(lastSeek.position_ms) > 440000 && Number(lastSeek.position_ms) < 460000)
  assert.equal(lastSeek.playing, "false")
  await page.evaluate(offset => {
    Object.assign(window.context.el.dataset, {videoId: "video-c", sessionId: "c", src: "", offsetMs: offset, autoplay: "false"})
    window.hook.updated.call(window.context)
  }, lastSeek.position_ms)
  await page.waitForFunction(() => document.querySelector("video").readyState === 0)
  assert.equal(await page.locator("video-skin").getAttribute("data-initial-loading"), null)
  await page.evaluate(() => {
    window.context.el.dataset.src = "/index.m3u8?session=c"
    window.hook.updated.call(window.context)
  })
  await page.waitForFunction(() => document.querySelector("video").readyState >= 2)
  assert.equal(await page.locator("video").evaluate(video => video.paused), true)
  assert.equal(await page.evaluate(() => window.events.some(([name, data]) => data.session_id === "c")), false)
  assert.ok(Math.abs((await readTime()).currentTime - Number(lastSeek.position_ms) / 1000) < 1)
  console.log("HLS: dragging commits once outside the generated fragment and preserves pause.")
  await page.locator("media-i18n").evaluate(element => { element.lang = "es" })
  await page.waitForFunction(() => document.querySelector("video-skin").shadowRoot.querySelector("media-play-button").getAttribute("aria-label") === "Reproducir")
  // A newly selected file gets its own opening, including time spent preparing HLS.
  await page.evaluate(() => {
    Object.assign(window.context.el.dataset, {fileId: "2", videoId: "video-2", src: ""})
    window.hook.updated.call(window.context)
  })
  assert.equal(await page.locator("video-skin").getAttribute("data-initial-loading"), "")
  await page.evaluate(() => {
    window.context.el.dataset.src = "/index.m3u8?file=2"
    window.hook.updated.call(window.context)
  })
  await page.waitForFunction(() => document.querySelector("video").readyState >= 2)
  assert.equal(await page.locator("video-skin").getAttribute("data-initial-loading"), null)
  console.log("Opening logo: initial load, later buffering, session replacement and new-file preparation passed.")
  // The diagnostic must precede fallback, which changes the server's session identity.
  const failurePage = await browser.newPage()
  await failurePage.route("**/sample.mp4", route => route.abort("failed"))
  await failurePage.goto(`http://127.0.0.1:${server.address().port}`, {waitUntil: "domcontentloaded"})
  await failurePage.waitForFunction(() => window.events?.some(([name]) => name === "playback_error"))
  const errorOrder = await failurePage.evaluate(() => window.events.map(([name, data]) =>
    name === "playback_diagnostic" ? data.diagnostic : name))
  assert.ok(errorOrder.indexOf("error") >= 0 && errorOrder.indexOf("error") < errorOrder.indexOf("playback_error"),
    `Expected error diagnostic before playback fallback: ${JSON.stringify(errorOrder)}`)
  await failurePage.close()
  console.log("Diagnostics: direct media error is observed before session-changing fallback.")
  assert.deepEqual(errors, [])
  await page.evaluate(() => window.hook.destroyed.call(window.context))
  console.log(`Video.js browser checks passed in Chromium ${browser.version()}.`)
} finally {
  await browser.close()
  await new Promise(resolve => server.close(resolve))
  await rm(temporary, {recursive: true, force: true})
}
