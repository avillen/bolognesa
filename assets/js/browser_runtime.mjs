import {createMediaCoordinator} from "./shared/media_coordinator.mjs"
import {initializeMusicPlayer} from "./music/music_bootstrap.mjs"

const runtimeKey = Symbol("bolognesa.browserRuntime")

/** One document owns media coordination, with or without an authenticated music host. */
export function initializeBrowserRuntime(document, {transport} = {}) {
  if (document[runtimeKey]) return document[runtimeKey]
  const mediaCoordinator = createMediaCoordinator()
  const musicPlayer = initializeMusicPlayer(document, {transport, coordinator: mediaCoordinator})
  const runtime = {
    musicSession: musicPlayer?.session || null,
    mediaCoordinator,
    destroy() {
      musicPlayer?.destroy()
      mediaCoordinator.destroy()
      delete document[runtimeKey]
    },
  }
  Object.defineProperty(document, runtimeKey, {value: runtime, configurable: true})
  return runtime
}

/** Hooks borrow document services; they do not own their lifetime. */
export const getBrowserRuntime = (window = globalThis.window) => window?.bolognesaRuntime
