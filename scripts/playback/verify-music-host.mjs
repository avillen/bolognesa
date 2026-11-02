// Browser regression for the rendered root host, using the isolated screenshot fixture.
import assert from "node:assert/strict"
import {chromium} from "playwright"
const base = process.env.BOLOGNESA_URL
const browser = await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, {exposeNetwork: "<loopback>"})
try {
  const page = await browser.newPage()
  await page.goto(`${base}/login`)
  assert.equal(await page.locator("#music-player-host").count(), 0, "public login page must not render the player host")
  const csrf = await page.locator('input[name="_csrf_token"]').inputValue()
  const response = await page.request.post(`${base}/login`, {form: {
    _csrf_token: csrf, "login[email]": "demo@example.test",
    "login[password]": "demo-password-only-for-screenshots",
  }})
  assert.ok(response.ok())
  await page.goto(`${base}/music`)
  await page.waitForFunction(() => document.querySelector('[data-phx-main]')?.classList.contains('phx-connected'))
  assert.equal(await page.locator("#music-player-host").count(), 1)
  assert.equal(await page.locator("#music-playback").count(), 1)
  assert.equal(await page.locator("#music-player-host").isHidden(), true)
  await page.evaluate(() => {
    const host = document.getElementById('music-player-host')
    const audio = document.getElementById('music-playback')
    const removed = []
    const observer = new MutationObserver(records => {
      for (const record of records) for (const node of record.removedNodes) {
        if (node === host || node.contains?.(host)) removed.push(node.nodeName)
      }
    })
    observer.observe(document.body, {childList: true, subtree: true})
    window.hostProbe = {host, audio, removed, observer}
  })
  for (const path of ['/movies', '/music', '/settings', '/music']) {
    await page.locator(`a[href^="${path}"][data-phx-link="redirect"]`).first().click()
    await page.waitForURL(url => url.pathname === path)
    await page.waitForFunction(() => document.querySelector('[data-phx-main]')?.classList.contains('phx-connected'))
    assert.deepEqual(await page.evaluate(() => {
      const probe = window.hostProbe
      return {same: document.getElementById('music-player-host') === probe?.host,
        audio: document.getElementById('music-playback') === probe?.audio,
        connected: probe?.audio.isConnected, removed: probe?.removed.length}
    }), {same: true, audio: true, connected: true, removed: 0})
  }
  console.log('PASS: rendered root host and single audio element remain continuously connected across four LiveView navigations; public login has no host')
} finally { await browser.close() }
