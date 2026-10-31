import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {chromium} from "playwright"

const base = process.env.BOLOGNESA_URL
const ids = JSON.parse(await readFile(process.env.BOLOGNESA_SCREENSHOT_IDS, "utf8"))
const browser = await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, {exposeNetwork: "<loopback>"})

async function waitConnected(page) {
  await page.waitForFunction(() => document.querySelector("[data-phx-main]")?.classList.contains("phx-connected"))
}

async function navigate(page, prefix, pathname) {
  const link = page.locator(`a[href^="${prefix}"][data-phx-link="redirect"]`).first()
  await link.click()
  await page.waitForURL(url => url.pathname === pathname)
  await waitConnected(page)
}

try {
  const page = await browser.newPage({viewport: {width: 1440, height: 900}})
  await page.goto(`${base}/login`)
  assert.equal(await page.locator("#music-player-host").count(), 0)
  const csrf = await page.locator('input[name="_csrf_token"]').inputValue()
  const login = await page.request.post(`${base}/login`, {form: {
    _csrf_token: csrf,
    "login[email]": "demo@example.test",
    "login[password]": "demo-password-only-for-screenshots",
  }})
  assert.ok(login.ok())
  await page.goto(`${base}/music?library_id=${ids.music_library}`)
  await waitConnected(page)
  assert.equal(await page.locator("#music-player-host").count(), 1)
  assert.equal(await page.locator("#music-playback").count(), 1)
  assert.equal(await page.locator("#music-player-host").isHidden(), true)

  await page.evaluate(() => {
    const host = document.getElementById("music-player-host")
    const audio = document.getElementById("music-playback")
    const removals = []
    const observer = new MutationObserver(records => {
      for (const record of records) for (const node of record.removedNodes) {
        if (node === host || node.contains?.(host)) removals.push(node.nodeName)
      }
    })
    observer.observe(document.body, {childList: true, subtree: true})
    window.persistentMusicProbe = {host, audio, removals, observer, plays: 0}
    audio.addEventListener("play", () => window.persistentMusicProbe.plays++)
  })
  await page.locator(`#play-track-${ids.music_track}`).click()
  await page.waitForFunction(() => {
    const audio = document.getElementById("music-playback")
    return audio && !audio.paused && audio.currentSrc.includes("/music/tracks/")
  })
  const initialSource = await page.locator("#music-playback").evaluate(audio => audio.currentSrc)
  const initialTime = await page.locator("#music-playback").evaluate(audio => audio.currentTime)
  assert.equal(await page.locator("#music-player-host").isHidden(), false)

  await navigate(page, "/movies", "/movies")
  await navigate(page, "/settings", "/settings")
  await navigate(page, "/music?", "/music")
  await page.waitForFunction(({source, time}) => {
    const probe = window.persistentMusicProbe
    return probe.host.isConnected && probe.audio.isConnected && probe.audio.currentSrc === source && probe.audio.currentTime > time + 0.5
  }, {source: initialSource, time: initialTime})
  assert.equal(await page.evaluate(() => window.persistentMusicProbe.removals.length), 0)

  const audio = page.locator("#music-playback")
  await page.locator('#music-player [data-player-action="toggle"]').click()
  await page.waitForFunction(() => document.getElementById("music-playback").paused)
  const pausedAt = await audio.evaluate(node => node.currentTime)
  const playCount = await page.evaluate(() => window.persistentMusicProbe.plays)
  await navigate(page, "/movies", "/movies")
  await navigate(page, "/music?", "/music")
  assert.ok(Math.abs((await audio.evaluate(node => node.currentTime)) - pausedAt) < 0.4)
  assert.equal(await page.evaluate(() => window.persistentMusicProbe.plays), playCount)

  await page.locator("#music-albums-link").click()
  await page.waitForURL(url => url.searchParams.get("view") === "albums")
  await page.locator(`#album-${ids.music_album}`).click()
  await page.waitForURL(url => url.searchParams.get("view") === "album")
  await page.locator("#play-album").click()
  await page.waitForFunction(id => window.bolognesaMusicPlayer.session.getSnapshot().selected?.id === id && !document.getElementById("music-playback").paused, ids.music_track)
  await navigate(page, "/movies", "/movies")
  await page.waitForFunction(id => window.bolognesaMusicPlayer.session.getSnapshot().selected?.id === id, ids.music_second_track, {timeout: 15_000})
  assert.equal(await page.evaluate(() => window.bolognesaMusicPlayer.session.getSnapshot().queueIndex), 1)
  await navigate(page, "/music?", "/music")
  await page.waitForFunction(id => document.querySelector(`#tracks-${id}[data-playback="playing"]`), ids.music_second_file)

  await page.evaluate(() => window.liveSocket.disconnect())
  await page.waitForFunction(() => !document.querySelector("[data-phx-main]")?.classList.contains("phx-connected"))
  const reconnectSource = await audio.evaluate(node => node.currentSrc)
  const reconnectTime = await audio.evaluate(node => node.currentTime)
  const reconnectPlayCount = await page.evaluate(() => window.persistentMusicProbe.plays)
  await page.evaluate(() => window.liveSocket.connect())
  await waitConnected(page)
  await page.waitForFunction(({source, time}) => {
    const audio = document.getElementById("music-playback")
    return audio.currentSrc === source && audio.currentTime > time + 0.25
  }, {source: reconnectSource, time: reconnectTime})
  assert.equal(await page.evaluate(() => window.persistentMusicProbe.plays), reconnectPlayCount)

  let intercepted = false
  await page.route(`${base}/music/playback/track`, async route => {
    const body = route.request().postDataJSON()
    if (!intercepted && body.track_id === ids.music_middle_track) {
      intercepted = true
      await route.fulfill({status: 503, contentType: "application/json", body: JSON.stringify({error: {code: "unavailable"}})})
    } else await route.continue()
  })
  await page.locator('#music-player [data-player-action="next"]').click()
  await page.waitForFunction(() => document.querySelector("#audio-error:not([hidden])")?.textContent.length > 0)
  assert.equal(await page.evaluate(() => window.bolognesaMusicPlayer.session.getSnapshot().queueIndex), 2)
  await page.unroute(`${base}/music/playback/track`)
  await page.locator('#music-player [data-player-action="retry"]').click()
  await page.waitForFunction(id => window.bolognesaMusicPlayer.session.getSnapshot().selected?.id === id, ids.music_middle_track)
  await page.locator('#music-player [data-player-action="next"]').click()
  await page.waitForFunction(() => window.bolognesaMusicPlayer.session.getSnapshot().error?.code === "unavailable")
  assert.equal(await page.evaluate(() => window.bolognesaMusicPlayer.session.getSnapshot().queueIndex), 3)
  assert.equal(await page.locator('#music-player [data-player-action="next"]').isDisabled(), true)

  await page.setViewportSize({width: 375, height: 812})
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= 375))
  const controlSizes = await page.locator("#music-player button").evaluateAll(nodes => nodes.filter(node => !node.hidden).map(node => ({action: node.dataset.playerAction, height: node.getBoundingClientRect().height, minHeight: getComputedStyle(node).minHeight})))
  console.log("Visible player controls:", JSON.stringify(controlSizes))
  assert.ok(controlSizes.every(control => control.height >= 44))
  await page.locator('#music-player [data-player-action="expand"]').click()
  assert.equal(await page.locator("#music-player").getAttribute("aria-modal"), "true")
  await page.keyboard.press("Escape")
  assert.equal(await page.locator("#music-player").getAttribute("aria-modal"), null)

  await page.locator('a[href="/"][data-phx-link="redirect"]').first().click()
  await page.waitForURL(url => url.pathname === "/")
  await page.locator("#logout-button").click()
  await page.waitForURL(url => url.pathname === "/login")
  assert.equal(await page.locator("#music-player-host").count(), 0)
  console.log("PASS: global host, navigation continuity, pause state, queue advancement outside Music, reconnection, retry/unavailable handling, 375px layout, keyboard expansion, and logout")
} finally {
  await browser.close()
}
