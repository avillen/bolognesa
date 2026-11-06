import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {join} from "node:path"
import {chromium} from "playwright"

const screenshotDir = process.env.BOLOGNESA_MUSIC_SCREENSHOTS
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
  if (pathname === "/music") {
    await page.locator("#music-songs-link").click()
    await page.waitForURL(url => url.searchParams.get("view") === "tracks")
  }
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
  assert.equal(await page.locator('#music-home-link[aria-current="page"]').count(), 1)
  await page.locator("#music-songs-link").click()
  await page.waitForURL(url => url.searchParams.get("view") === "tracks")
  assert.equal(await page.locator("#music-player-host").count(), 1)
  assert.equal(await page.locator("#music-playback").count(), 1)
  assert.equal(await page.locator("#music-player-host").isHidden(), true)
  const search = page.getByLabel("Buscar canciones, artistas o álbumes")
  const searchBounds = await search.boundingBox()
  assert.ok(searchBounds && searchBounds.width >= 100 && searchBounds.height >= 44, "music search must be visible")

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
  await page.setViewportSize({width: 320, height: 568})
  await page.locator(`#play-track-${ids.music_second_track}`).click()
  await page.waitForFunction(id => window.bolognesaRuntime.musicSession.getSnapshot().selected?.id === id && !document.getElementById("music-playback").paused, ids.music_second_track)
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight))
  const initialList = await page.evaluate(() => {
    const list = document.getElementById("music-tracks")
    window.listeningUpdateProbe = {list, rows: [...list.children], scrollY: window.scrollY}
    return {order: [...list.children].map(row => row.id), scrollY: window.scrollY}
  })
  assert.ok(initialList.scrollY > 0, "album view must be scrolled to test stability")
  await page.waitForFunction(id => {
    const row = document.querySelector(`#play-track-${id}`)?.closest("article")
    return row?.querySelector(".music-track-last-played")?.textContent.includes("Última reproducción:")
  }, ids.music_second_track, {timeout: 10000})
  const afterListening = await page.evaluate(() => ({
    listConnected: window.listeningUpdateProbe.list.isConnected,
    rowsConnected: window.listeningUpdateProbe.rows.every(row => row.isConnected),
    order: [...document.getElementById("music-tracks").children].map(row => row.id),
    scrollY: window.scrollY,
  }))
  assert.equal(afterListening.listConnected, true, "list must stay mounted")
  assert.equal(afterListening.rowsConnected, true, "track rows must stay mounted")
  assert.deepEqual(afterListening.order, initialList.order, "track order must remain stable")
  assert.ok(Math.abs(afterListening.scrollY - initialList.scrollY) <= 2, "scroll position must remain stable")
  await page.locator("#music-tracks article[data-state=ready] h2").first().evaluate(title => {
    title.dataset.originalTitle = title.textContent
    title.textContent = "A deliberately long track title that tests wrapping and alignment across narrow and wide screens"
  })
  for (const width of [320, 375, 640, 641, 1440]) {
    await page.setViewportSize({width, height: 900})
    const layout = await page.locator("#music-tracks article[data-state=ready]").evaluateAll(rows => rows.map(row => {
      const rect = element => element.getBoundingClientRect()
      const center = box => (box.top + box.bottom) / 2
      const copy = rect(row.querySelector(".music-track-copy"))
      const meta = rect(row.querySelector(".music-track-meta"))
      const play = rect(row.querySelector(".music-track-play"))
      const queue = rect(row.querySelector('[data-music-action="append-track"]'))
      const menu = rect(row.querySelector(".music-action-menu summary"))
      return {copyLeft: copy.left, metaLeft: meta.left, metaCenter: center(meta), playCenter: center(play), queueCenter: center(queue), menuCenter: center(menu), rowRight: rect(row).right, scrollWidth: row.scrollWidth, clientWidth: row.clientWidth}
    }))
    assert.ok(layout.length >= 2, "track alignment needs multiple rows")
    for (const row of layout) {
      assert.ok(Math.abs(row.playCenter - row.queueCenter) < 2 && Math.abs(row.playCenter - row.menuCenter) < 2, `track controls must align at ${width}px`)
      assert.ok(row.scrollWidth <= row.clientWidth, `track row must not overflow at ${width}px`)
      if (width <= 640) assert.ok(Math.abs(row.metaLeft - row.copyLeft) < 2, `metadata must align with title at ${width}px`)
      else assert.ok(Math.abs(row.metaCenter - row.playCenter) < 2, `metadata and controls must be vertically aligned at ${width}px`)
    }
  }
  await page.locator("#music-tracks article[data-state=ready] h2").first().evaluate(title => {
    title.textContent = title.dataset.originalTitle
    delete title.dataset.originalTitle
  })
  await page.setViewportSize({width: 320, height: 568})
  await page.locator("#play-album").click()
  await page.waitForFunction(id => window.bolognesaRuntime.musicSession.getSnapshot().selected?.id === id && !document.getElementById("music-playback").paused, ids.music_track)
  await audio.evaluate(node => { node.playbackRate = 0.25 })
  await page.setViewportSize({width: 320, height: 568})
  const mobileSearchBounds = await search.boundingBox()
  assert.ok(mobileSearchBounds && mobileSearchBounds.width >= 100 && mobileSearchBounds.height >= 44, "music search must be visible on mobile")
  const currentRow = page.locator(`#play-track-${ids.music_track}`).locator("xpath=..")
  await currentRow.waitFor({state: "visible"})
  const currentPlay = currentRow.locator(".music-track-play")
  const currentStyle = await currentPlay.evaluate(node => ({background: getComputedStyle(node).backgroundColor, color: getComputedStyle(node).color}))
  assert.notEqual(currentStyle.background, "rgba(0, 0, 0, 0)", "playing control must have a visible background")
  assert.notEqual(currentStyle.background, currentStyle.color)
  await currentPlay.hover()
  const hoverStyle = await currentPlay.evaluate(node => ({background: getComputedStyle(node).backgroundColor, color: getComputedStyle(node).color}))
  assert.notEqual(hoverStyle.background, "rgba(0, 0, 0, 0)", "hovered control must have a visible background")
  assert.notEqual(hoverStyle.background, hoverStyle.color)
  const otherPlay = page.locator(`#play-track-${ids.music_second_track}`)
  await otherPlay.hover()
  const otherHover = await otherPlay.evaluate(node => ({background: getComputedStyle(node).backgroundColor, color: getComputedStyle(node).color}))
  assert.notEqual(otherHover.background, "rgba(0, 0, 0, 0)", "hovered control must have a visible background")
  assert.notEqual(otherHover.background, otherHover.color)
  assert.equal(await currentRow.locator(".music-track-art").isVisible(), false)
  const lastMenu = page.locator("#music-tracks article details").last()
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight))
  await lastMenu.locator("summary").scrollIntoViewIfNeeded()
  await lastMenu.locator("summary").click()
  const menuAction = await lastMenu.locator("button").last().boundingBox()
  const miniPlayer = await page.locator("#music-player-host").boundingBox()
  assert.ok(menuAction && miniPlayer && menuAction.y + menuAction.height <= miniPlayer.y, "last track menu is covered by the player")
  await page.keyboard.press("Escape")
  await page.setViewportSize({width: 1440, height: 900})
  const trackMenu = currentRow.locator("details").first()
  await trackMenu.locator("summary").click()
  assert.equal(await trackMenu.evaluate(node => node.open), true)
  const menuBounds = await trackMenu.locator("button").evaluateAll(buttons => buttons.map(button => ({left: button.getBoundingClientRect().left, width: button.getBoundingClientRect().width})))
  assert.equal(menuBounds.length, 2)
  assert.equal(menuBounds[0].left, menuBounds[1].left)
  assert.equal(menuBounds[0].width, menuBounds[1].width)
  await page.keyboard.press("Escape")
  assert.equal(await trackMenu.evaluate(node => node.open), false)
  await trackMenu.locator("summary").click()
  await page.locator(".music-title").click()
  assert.equal(await trackMenu.evaluate(node => node.open), false)
  await page.locator('#music-player [data-player-action="expand"]').click()
  if (screenshotDir) await page.screenshot({path: join(screenshotDir, "player-playing.png"), animations: "disabled"})
  await page.locator('#music-player [data-player-action="queue"]').click()
  const queueMenu = page.locator("#music-up-next details").first()
  await queueMenu.locator("summary").click()
  const queueAction = queueMenu.locator('button[data-player-action="remove-upcoming"]')
  const normalBackground = await queueAction.evaluate(node => getComputedStyle(node).backgroundColor)
  await queueAction.hover()
  const hoverBackground = await queueAction.evaluate(node => getComputedStyle(node).backgroundColor)
  assert.notEqual(hoverBackground, normalBackground, "queue menu hover must be visible")
  await page.keyboard.press("Tab")
  assert.notEqual(await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle), "none", "keyboard focus must remain visible")
  await page.keyboard.press("Escape")
  assert.equal(await queueMenu.evaluate(node => node.open), false)
  assert.equal(await page.locator("#music-player").getAttribute("aria-modal"), "true")
  await page.keyboard.press("Escape")
  await audio.evaluate(node => { node.playbackRate = 1 })
  await navigate(page, "/movies", "/movies")
  await page.waitForFunction(id => window.bolognesaRuntime.musicSession.getSnapshot().selected?.id === id, ids.music_second_track, {timeout: 15_000})
  assert.equal(await page.evaluate(() => window.bolognesaRuntime.musicSession.getSnapshot().queueIndex), 1)
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
  assert.equal(await page.evaluate(() => window.bolognesaRuntime.musicSession.getSnapshot().queueIndex), 2)
  await page.unroute(`${base}/music/playback/track`)
  await page.locator('#music-player [data-player-action="retry"]').click()
  await page.waitForFunction(id => window.bolognesaRuntime.musicSession.getSnapshot().selected?.id === id, ids.music_middle_track)
  await page.locator('#music-player [data-player-action="next"]').click()
  await page.waitForFunction(() => window.bolognesaRuntime.musicSession.getSnapshot().error?.code === "unavailable")
  assert.equal(await page.evaluate(() => window.bolognesaRuntime.musicSession.getSnapshot().queueIndex), 3)
  assert.equal(await page.locator('#music-player [data-player-action="next"]').isDisabled(), true)

  await page.setViewportSize({width: 375, height: 812})
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= 375))
  const controlSizes = await page.locator("#music-player button").evaluateAll(nodes => nodes.filter(node => node.getClientRects().length > 0).map(node => ({action: node.dataset.playerAction, height: node.getBoundingClientRect().height, minHeight: getComputedStyle(node).minHeight})))
  console.log("Visible player controls:", JSON.stringify(controlSizes))
  assert.ok(controlSizes.every(control => control.height >= 44))
  await page.locator('#music-player [data-player-action="expand"]').click()
  assert.equal(await page.locator("#music-player").getAttribute("aria-modal"), "true")
  await page.keyboard.press("Escape")
  assert.equal(await page.locator("#music-player").getAttribute("aria-modal"), null)

  // Exercise the responsive player without changing the audio session when opening its views.
  for (const [width, height] of [[320, 568], [390, 844], [768, 1024], [1440, 900], [1920, 1080]]) {
    await page.setViewportSize({width, height})
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `horizontal overflow at ${width}`)
    assert.equal(await page.locator('#music-player [data-player-action="next"]').isVisible(), true)
    const source = await audio.evaluate(node => node.currentSrc)
    const paused = await audio.evaluate(node => node.paused)
    await page.locator('#music-player [data-player-action="expand"]').click()
    assert.equal(await page.locator('#music-player [data-player-action="collapse"]').isVisible(), true)
    if (screenshotDir) await page.screenshot({path: join(screenshotDir, `player-${width}.png`), animations: "disabled"})
    const overflow = await page.evaluate(() => {
      const player = document.querySelector("#music-player")
      return {document: document.documentElement.scrollWidth, viewport: innerWidth, scroll: player.scrollWidth, client: player.clientWidth, children: [...player.children].filter(el => el.getBoundingClientRect().right > innerWidth).map(el => ({tag: el.tagName, action: el.dataset.playerAction, text: el.textContent.slice(0, 80), width: el.getBoundingClientRect().width, right: el.getBoundingClientRect().right}))}
    })
    assert.ok(overflow.document <= overflow.viewport && overflow.scroll <= overflow.client, `expanded overflow at ${width}: ${JSON.stringify(overflow)}`)
    const expandedControls = page.locator('#music-player [data-player-action="toggle"]')
    await expandedControls.scrollIntoViewIfNeeded()
    const bounds = await expandedControls.boundingBox()
    assert.ok(bounds && bounds.width >= 44 && bounds.height >= 44 && bounds.y >= 0 && bounds.y + bounds.height <= height, `expanded controls clipped at ${width}`)
    await page.locator('#music-player [data-player-action="queue"]').click()
    assert.equal(await page.locator('#music-up-next').isVisible(), true)
    if (width < 1080) {
      const back = await page.locator('#music-player [data-player-action="queue"]').boundingBox()
      const current = await page.locator('.music-queue-current').boundingBox()
      assert.ok(back && current && back.y + back.height <= current.y, `queue header overlaps current track at ${width}`)
    }
    if (screenshotDir) await page.screenshot({path: join(screenshotDir, `queue-${width}.png`), animations: "disabled"})
    assert.equal(await audio.evaluate(node => node.currentSrc), source)
    assert.equal(await audio.evaluate(node => node.paused), paused)
    await page.locator('#music-player [data-player-action="queue"]').click()
    await page.keyboard.press("Escape")
    assert.equal(await page.locator('#music-player [data-player-action="expand"]').evaluate(node => node === document.activeElement), true)
  }

  await page.locator('a[href="/"][data-phx-link="redirect"]').first().click()
  await page.waitForURL(url => url.pathname === "/")
  await page.locator("#logout-button").click()
  await page.waitForURL(url => url.pathname === "/login")
  assert.equal(await page.locator("#music-player-host").count(), 0)
  console.log("PASS: global host, navigation continuity, pause state, queue advancement outside Music, reconnection, retry/unavailable handling, 375px layout, keyboard expansion, and logout")
} finally {
  await browser.close()
}
