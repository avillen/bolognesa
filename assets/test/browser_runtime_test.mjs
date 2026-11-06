import test from "node:test"
import assert from "node:assert/strict"
import {initializeBrowserRuntime} from "../js/browser_runtime.mjs"

class Media extends EventTarget {
  paused = false
  pause() { this.paused = true }
}
test("document coordination exists without a music host and initializes once", () => {
  const document = {querySelector: () => null}
  const runtime = initializeBrowserRuntime(document)
  assert.equal(runtime.musicSession, null)
  assert.equal(initializeBrowserRuntime(document), runtime)
  const first = new Media(), second = new Media()
  runtime.mediaCoordinator.register(first)
  const unregister = runtime.mediaCoordinator.register(second)
  second.dispatchEvent(new Event("playing"))
  assert.equal(first.paused, true)
  assert.equal(second.paused, false)
  unregister()
  first.paused = false
  second.dispatchEvent(new Event("playing"))
  assert.equal(first.paused, false)
  runtime.destroy()
  assert.notEqual(initializeBrowserRuntime(document), runtime)
})
