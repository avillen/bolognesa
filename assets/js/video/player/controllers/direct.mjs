/** Direct-file source lifecycle; emits the existing LiveView media contract. */
export function createDirectController({video, config, pushEvent, onReady}) {
  let reported = false
  const onError = () => {
    if (reported) return
    reported = true
    const seconds = video.currentTime
    const position = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds * 1000)) : 0
    pushEvent("playback_error", {file_id: config.fileId, position_ms: String(position)})
  }
  const onEnded = () => pushEvent("playback_ended", {file_id: config.fileId})
  video.addEventListener("ended", onEnded)
  video.addEventListener("error", onError)
  if (onReady) video.addEventListener("loadedmetadata", onReady, {once: true})
  if (video.error) onError()
  video.src = config.src || ""
  return {
    update() {},
    destroy() {
      video.removeEventListener("ended", onEnded)
      video.removeEventListener("error", onError)
      if (onReady) video.removeEventListener("loadedmetadata", onReady)
    },
  }
}
