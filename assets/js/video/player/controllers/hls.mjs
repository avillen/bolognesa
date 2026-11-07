/** Authorized HLS source lifecycle. Positions sent to LiveView use whole-file milliseconds. */
export function createHlsController({video, config, pushEvent, reportPlaybackError, onReady, Hls}) {
  const sessionId = config.sessionId
  const offsetMs = Number(config.offsetMs), durationMs = Number(config.durationMs)
  let resuming = false, serverPaused = false, destroyed = false, hls = null
  const currentPosition = () => Math.min(durationMs || Infinity,
    offsetMs + Math.max(0, Math.floor(video.currentTime * 1000)))

  video.fileTimeline = {
    offset: offsetMs / 1000, duration: durationMs / 1000,
    seek(seconds) {
      if (destroyed || video.fileTimeline.pending) return
      video.fileTimeline.pending = true
      resuming = true
      pushEvent("playback_seek", {session_id: sessionId, position_ms: String(Math.floor(seconds * 1000)),
        playing: String(!video.paused)})
    },
  }
  const onPause = () => {
    if (resuming || video.ended) return
    serverPaused = true
    pushEvent("playback_pause", {session_id: sessionId})
  }
  const onPlay = () => {
    if (!serverPaused && config.pausedServer !== "true") return
    serverPaused = false
    resuming = true
    pushEvent("playback_resume", {session_id: sessionId, position_ms: String(currentPosition())})
  }
  const onError = (diagnose = false) => {
    if (destroyed || serverPaused || resuming) return
    if (diagnose === true) reportPlaybackError?.()
    pushEvent("transcode_error", {session_id: sessionId})
  }
  const onEnded = () => {
    serverPaused = true
    hls?.stopLoad()
    pushEvent("playback_ended", {session_id: sessionId})
  }
  const ready = () => {
    if (destroyed) return
    if (onReady) onReady()
    else if (config.autoplay === "true") video.play().catch(() => {})
  }
  const listeners = {pause: onPause, play: onPlay, error: onError, ended: onEnded}
  for (const [name, listener] of Object.entries(listeners)) video.addEventListener(name, listener)
  attachSource()

  function attachSource() {
    if (config.transport === "hls_js" && Hls.isSupported()) {
      hls = new Hls({lowLatencyMode: false, liveSyncDurationCount: 3, startPosition: 0})
      hls.on(Hls.Events.MANIFEST_PARSED, ready)
      hls.on(Hls.Events.ERROR, (_event, data) => { if (data.fatal) onError(true) })
      hls.loadSource(config.src)
      hls.attachMedia(video)
      return
    }
    if (config.transport === "native_hls" && video.canPlayType("application/vnd.apple.mpegurl")) {
      video.src = config.src
      video.addEventListener("loadedmetadata", ready, {once: true})
      return
    }
    onError(true)
  }
  return {
    update(nextConfig) {
      config = nextConfig
      if (video.fileTimeline?.pending) return
      if (config.pausedServer === "true") {
        serverPaused = true
        video.pause()
        return
      }
      serverPaused = false
      resuming = false
    },
    destroy() {
      destroyed = true
      for (const [name, listener] of Object.entries(listeners)) video.removeEventListener(name, listener)
      video.removeEventListener("loadedmetadata", ready)
      hls?.destroy()
      delete video.fileTimeline
    },
  }
}
