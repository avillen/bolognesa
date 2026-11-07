// Native, disposable demo only. Actual LiveView, production hooks and paced FFmpeg.
// Args: base URL, browser-ids.json from seed-negotiation-check.exs, credentials JSON.
// Credentials stay local; reports contain only synthetic fixture names and browser facts.
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {chromium} from "playwright"

const [baseUrl, idsPath, credentialsPath] = process.argv.slice(2)
assert.ok(baseUrl && idsPath && credentialsPath, "Pass URL, synthetic IDs and credentials JSON")
const ids = JSON.parse(await readFile(idsPath, "utf8"))
const credentials = JSON.parse(await readFile(credentialsPath, "utf8"))
const browser = await chromium.launch({headless: true, channel: process.env.BOLOGNESA_TEST_BROWSER_CHANNEL})
let page
try {
  console.log(JSON.stringify({browser: browser.version(), device: "desktop", nativeHls: "not verified"}))
  page = await browser.newPage()
  page.setDefaultTimeout(20000)
  await page.goto(`${baseUrl}/login`)
  const csrf = await page.locator('input[name="_csrf_token"]').inputValue()
  const login = await page.request.post(`${baseUrl}/login`, {form: {
    _csrf_token: csrf, "login[email]": credentials.email, "login[password]": credentials.password,
  }})
  assert.ok(login.ok() && !new URL(login.url()).pathname.includes("login"), "Synthetic account login succeeds")
  console.log("Authenticated synthetic demo account.")

  // Exercise each delivery path with a controlled original-file rejection. This is
  // explicitly a capability-report injection, not a claim Chrome rejects every MKV/HEVC.
  await page.addInitScript(() => {
    const original = HTMLMediaElement.prototype.canPlayType
    HTMLMediaElement.prototype.canPlayType = function(type) {
      if (window.rejectOriginal && (type.includes("matroska") || /hvc1|hev1/.test(type))) return ""
      return original.call(this, type)
    }
  })
  await page.goto(`${baseUrl}/movies/${ids.movie}`)
  await page.waitForFunction(() => window.liveSocket?.isConnected())
  await page.locator("#movie-playback-options > summary").click()
  await page.locator(`#movie-play-${ids.fixtures["direct.mp4"]}`).click()
  await page.locator("video-skin").waitFor()
  await page.waitForFunction(file => document.querySelector("#movie-video-frame")?.dataset.fileId === String(file), ids.fixtures["direct.mp4"])
  await page.evaluate(() => {
    window.rejectOriginal = true
    const video = document.querySelector("video")
    video.muted = true
    const skin = document.querySelector("video-skin")
    const ancestors = new Set()
    for (let node = video; node; node = node.parentNode) ancestors.add(node)
    const removed = []
    const observer = new MutationObserver(records => {
      for (const record of records) for (const node of record.removedNodes) {
        if (ancestors.has(node)) removed.push(node.nodeName)
      }
    })
    observer.observe(document.body, {childList: true, subtree: true})
    window.stablePlayer = {video, skin, observer, removed}
  })

  const ready = async prefix => {
    await page.waitForFunction(prefix => {
      const frame = document.querySelector(`#${prefix}-video-frame`)
      return frame?.dataset.playbackPhase === "ready" && document.querySelector("video")?.readyState >= 2
    }, prefix)
    await page.locator("video").evaluate(video => {video.muted = true})
    if (await page.locator("video").evaluate(video => video.paused)) {
      await page.locator("video").hover()
      await page.locator(`#${prefix}-video-frame media-play-button`).click()
    }
    await page.waitForFunction(prefix => {
      const frame = document.querySelector(`#${prefix}-video-frame`)
      const video = document.querySelector("video")
      return !video.paused && video.currentTime > 0.2 &&
        (!frame.dataset.sessionId || frame.dataset.pausedServer === "false")
    }, prefix)
  }
  const stable = async () => {
    assert.deepEqual(await page.evaluate(() => {
      const {video, skin, removed} = window.stablePlayer
      return {video: video === document.querySelector("video"), skin: skin === document.querySelector("video-skin"), removed}
    }), {video: true, skin: true, removed: []})
  }

  const select = async file => {
    const before = await page.locator("#movie-video-frame").getAttribute("data-attempt-id")
    await page.locator(`#movie-play-${file}`).click()
    await page.waitForFunction(({file, before}) => {
      const frame = document.querySelector("#movie-video-frame")
      return frame?.dataset.fileId === String(file) && frame.dataset.attemptId !== before
    }, {file, before})
  }

  for (const [fixture, mode] of [
    ["direct.mp4", "direct"], ["remux.mkv", "remux"], ["audio.mkv", "audio_conversion"],
    ["video.mp4", "video_conversion"], ["both.mp4", "full_conversion"], ["silent.mkv", "remux"],
  ]) {
    const file = ids.fixtures[fixture]
    await select(file)
    await ready("movie")
    const frame = page.locator("#movie-video-frame")
    const session = await frame.getAttribute("data-session-id")
    assert.equal(Boolean(session), mode !== "direct")
    const expectedLabels = {direct: "Reproducción directa", remux: "Remultiplexado sin conversión",
      audio_conversion: "Transcodificación de audio", video_conversion: "Transcodificación de vídeo",
      full_conversion: "Transcodificación de vídeo y audio"}
    assert.ok((await page.locator("#playback-mode").textContent()).includes(expectedLabels[mode]))
    await page.locator("video").hover()
    await page.locator("#movie-video-frame media-play-button").click()
    await page.waitForFunction(() => document.querySelector("video").paused)
    if (session) await page.waitForFunction(() => document.querySelector("#movie-video-frame").dataset.pausedServer === "true")
    await page.locator("video").hover()
    await page.locator("#movie-video-frame media-play-button").click()
    await page.waitForFunction(() => !document.querySelector("video").paused)
    // Commit a seek through the real player control, including HLS session replacement.
    const previous = session
    await page.locator("#movie-video-frame media-time-slider").focus()
    await page.keyboard.press("ArrowRight")
    if (previous) {
      await page.waitForFunction(previous => {
        const frame = document.querySelector("#movie-video-frame")
        return frame.dataset.sessionId !== previous && frame.dataset.playbackPhase === "ready"
      }, previous)
    }
    await ready("movie")
    await stable()
    console.log(JSON.stringify({fixture, mode, transport: await frame.getAttribute("data-transport"),
      originalRejectionInjected: fixture !== "direct.mp4", startup: true, pauseResume: true, seek: true, stable: true}))
  }

  // Ambiguous native code 4 remains terminal, then the user's explicit action starts HLS.
  await select(ids.fixtures["direct.mp4"])
  await ready("movie")
  await page.locator("video").hover()
  await page.locator("media-fullscreen-button").click()
  await page.waitForFunction(() => !!document.fullscreenElement)
  await page.locator("video").evaluate(video => {
    Object.defineProperty(video, "error", {configurable: true, value: {code: 4}})
    video.dispatchEvent(new Event("error"))
    delete video.error
  })
  await page.locator("#movie-playback-error").waitFor()
  assert.equal(await page.locator("#movie-playback-preparing").count(), 0)
  await page.locator(".bolognesa-playback-feedback [data-playback-compatible]").click()
  await ready("movie")
  await stable()
  assert.ok(await page.evaluate(() => document.fullscreenElement === window.stablePlayer.skin))
  console.log(JSON.stringify({explicitCompatible: true, nativeErrorInjected: 4, fullscreen: true, stable: true}))
  await page.evaluate(() => document.exitFullscreen())

  // A correlated native decode failure spends one recovery; a second is terminal.
  await select(ids.fixtures["direct.mp4"])
  await ready("movie")
  // Keep the injected failure well before EOF and separate from checkpoint restoration.
  await page.locator("video").evaluate(video => {video.currentTime = 1})
  await page.waitForFunction(() => !document.querySelector("video").seeking && document.querySelector("video").currentTime < 3)
  const decodeFailure = () => page.locator("video").evaluate(video => {
    Object.defineProperty(video, "error", {configurable: true, value: {code: 3}})
    video.dispatchEvent(new Event("error"))
    delete video.error
  })
  await decodeFailure()
  await page.waitForFunction(() => !!document.querySelector("#movie-video-frame").dataset.sessionId)
  await ready("movie")
  await decodeFailure()
  await page.locator("#movie-playback-error").waitFor()
  assert.equal(await page.locator("#movie-playback-preparing").count(), 0)
  await stable()
  console.log(JSON.stringify({decodeErrorInjected: 3, automaticRecoveries: 1, secondFailureTerminal: true}))

  // Abort a real authorized original download; this must not start conversion.
  await page.route(`**/movies/${ids.movie}/media/${ids.fixtures["direct.mp4"]}`, route => route.abort("failed"))
  await select(ids.fixtures["direct.mp4"])
  await page.locator("#movie-playback-error").waitFor()
  assert.equal(await page.locator("#movie-playback-preparing").count(), 0)
  assert.equal(await page.locator("#movie-video-frame").getAttribute("data-session-id"), null)
  await page.unroute(`**/movies/${ids.movie}/media/${ids.fixtures["direct.mp4"]}`)
  console.log(JSON.stringify({actualOriginalDownloadAborted: true, automaticConversion: false}))

  // Real EOF events and LiveView patches through part and episode continuation.
  await page.goto(`${baseUrl}/episodes/${ids.episode}?part=1`)
  await ready("episode")
  await page.evaluate(() => {
    const video = document.querySelector("video"), skin = document.querySelector("video-skin")
    window.continuation = {video, skin}
  })
  await page.locator("video").hover()
  await page.locator("media-fullscreen-button").click()
  await page.waitForFunction(() => !!document.fullscreenElement)
  for (const next of ["part", "episode"]) {
    await page.locator("video").evaluate(video => {video.currentTime = video.duration - 0.3; return video.play()})
    if (next === "part") await page.waitForURL(url => url.searchParams.get("part") === "2")
    else await page.waitForURL(url => url.pathname === `/episodes/${ids.next_episode}`)
    await ready("episode")
    assert.ok(await page.evaluate(() => document.querySelector("video") === window.continuation.video &&
      document.querySelector("video-skin") === window.continuation.skin && document.fullscreenElement === window.continuation.skin))
    console.log(JSON.stringify({eofContinuation: next, fullscreen: true, stable: true}))
  }
} catch (error) {
  if (page && !page.isClosed()) await page.screenshot({path: "tmp/task7-browser-failure.png"})
  if (page && !page.isClosed()) console.error(JSON.stringify(await page.evaluate(() => {
    const frame = document.querySelector("#movie-video-frame, #episode-video-frame")
    const video = document.querySelector("video")
    return {path: location.pathname, phase: frame?.dataset.playbackPhase,
      session: !!frame?.dataset.sessionId, playbackError: frame?.dataset.playbackError,
      media: video && {readyState: video.readyState, paused: video.paused,
        currentTime: video.currentTime, error: video.error?.code}}
  })))
  throw error
} finally {
  await browser.close()
}
