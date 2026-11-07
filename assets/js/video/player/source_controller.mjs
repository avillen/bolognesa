import {createDirectController} from "./controllers/direct.mjs"
import {createHlsController} from "./controllers/hls.mjs"

/** Replaces sources within a stable mounted player; recovery may defer attachment. */
export function createSourceController(hook, {Hls, direct = createDirectController, hls = createHlsController}) {
  const {video, el, recovery} = hook
  let controller = null, signature = null, playbackError = null
  function clearSource() {
    controller?.destroy()
    controller = null
    video.pause()
    delete video.fileTimeline
    video.removeAttribute("src")
    video.load()
  }
  function update() {
    const config = {...el.dataset}
    config.src = config.playbackError ? "" : config.src || ""
    const nextSignature = `${config.attemptId || ""}:${config.recoveryScope}:${config.videoId}:${config.src}:${config.playbackError || ""}:${config.playbackPhase || ""}:${config.transport || ""}`
    if (signature === nextSignature) {
      video.dataset.pausedServer = config.pausedServer
      controller?.update(config)
      return
    }
    signature = nextSignature
    const retrying = !!playbackError && !config.playbackError
    playbackError = config.playbackError
    if (config.playbackPhase === "checking" || config.playbackPhase === "preparing") {
      recovery.suspend()
      clearSource()
      return
    }
    recovery.beforeSourceChange()
    clearSource()
    video.id = config.videoId
    for (const key of Object.keys(video.dataset)) delete video.dataset[key]
    Object.assign(video.dataset, config)
    if (!config.src || config.playbackError || !recovery.source({retry: retrying})) return
    const create = config.sessionId ? hls : direct
    controller = create({video, config, Hls, pushEvent: (...args) => hook.pushEvent(...args),
      reportPlaybackError: () => hook.diagnostics.reportError(), onReady: () => recovery.ready()})
  }
  return {update, retry() { signature = null; update() }, destroy: clearSource}
}
