// Exercise the real LiveView patch, rather than replacing hook attributes by hand.
// Run through run-readme-screenshots.sh --verify-fullscreen for isolated demo data.
import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {chromium} from "playwright"

const baseUrl = process.env.BOLOGNESA_URL ?? "http://127.0.0.1:4001"
const ids = JSON.parse(await readFile(process.env.BOLOGNESA_SCREENSHOT_IDS, "utf8"))
assert.ok(ids.next_episode, "Seed the fullscreen continuation fixture")
const browser = process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS
  ? await chromium.connect(process.env.BOLOGNESA_SCREENSHOT_BROWSER_WS, {exposeNetwork: "<loopback>"})
  : await chromium.launch({headless: true, channel: process.env.BOLOGNESA_TEST_BROWSER_CHANNEL})
try {
  const page = await browser.newPage()
  page.setDefaultTimeout(15000)
  await page.goto(`${baseUrl}/login`)
  const csrf = await page.locator('input[name="_csrf_token"]').inputValue()
  const login = await page.request.post(`${baseUrl}/login`, {form: {
    _csrf_token: csrf,
    "login[email]": "demo@example.test",
    "login[password]": "demo-password-only-for-screenshots",
  }})
  assert.ok(login.ok(), "Synthetic account login succeeds")

  for (const navigation of ["automatic", "next link"]) {
    await page.goto(`${baseUrl}/episodes/${ids.episode}`)
    await page.waitForFunction(() => document.querySelector("video-skin"))
    await page.evaluate(() => {
      const video = document.querySelector("video")
      const skin = document.querySelector("video-skin")
      const ancestors = new Set()
      for (let node = skin; node; node = node.parentNode) ancestors.add(node)
      const removed = []
      const observer = new MutationObserver(records => {
        for (const record of records) {
          for (const node of record.removedNodes) {
            if (ancestors.has(node)) removed.push(node.nodeName)
          }
        }
      })
      observer.observe(document.body, {childList: true, subtree: true})
      window.fullscreenRegression = {video, skin, removed, observer}
    })
    await page.locator("media-fullscreen-button").click()
    await page.waitForFunction(() => !!document.fullscreenElement)
    if (navigation === "automatic") {
      // Deliver the native event to the production hook and let the server find the next episode.
      await page.locator("video").evaluate(video => video.dispatchEvent(new Event("ended")))
    } else {
      // The link is outside fullscreen; invoke its real click handler without leaving fullscreen.
      await page.locator("#episode-next").evaluate(link => link.click())
    }
    await page.waitForURL(`${baseUrl}/episodes/${ids.next_episode}`)
    await page.waitForFunction(id =>
      document.querySelector("#episode-video-frame")?.dataset.src?.includes(`/episodes/${id}/`),
    ids.next_episode)
    const result = await page.evaluate(async () => {
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
      const {video, skin, removed, observer} = window.fullscreenRegression
      observer.disconnect()
      return {
        fullscreen: document.fullscreenElement === skin,
        sameVideo: video === document.querySelector("video"),
        sameSkin: skin === document.querySelector("video-skin"),
        removed,
      }
    })
    assert.deepEqual(result, {fullscreen: true, sameVideo: true, sameSkin: true, removed: []},
      `${navigation} must keep the fullscreen subtree continuously connected`)
    await page.evaluate(() => document.exitFullscreen())
    console.log(`Episode ${navigation}: real LiveView patch preserves fullscreen and connected ancestors.`)
  }
} finally {
  await browser.close()
}
