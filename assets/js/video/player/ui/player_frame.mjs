export function createPlayerFrame({el, video, pushEvent}) {
  const document = el.ownerDocument
  // Connect the player before its skin so all controls find the player's context.
  const player = document.createElement("bolognesa-video-player")
  const skin = document.createElement("video-skin")
  video.replaceWith(player)
  skin.append(video)
  player.append(skin)
  // Slotted feedback remains visible inside the skin's fullscreen container.
  const feedback = document.createElement("div")
  feedback.className = "bolognesa-playback-feedback"
  feedback.setAttribute("role", "alert")
  const message = document.createElement("p")
  const retry = document.createElement("button")
  retry.type = "button"
  const onRetry = () => {
    const fileId = el.dataset.retryFileId
    if (fileId) pushEvent("play", {file_id: fileId})
  }
  retry.addEventListener("click", onRetry)
  const compatible = document.createElement("button")
  compatible.type = "button"
  compatible.setAttribute("data-playback-compatible", "")
  const onCompatible = () => {
    if (el.dataset.compatiblePlaybackAvailable === "true") pushEvent("playback_compatible", {})
  }
  compatible.addEventListener("click", onCompatible)
  feedback.append(message, retry, compatible)
  skin.append(feedback)
  const onFullscreenChange = () => skin.toggleAttribute("data-player-fullscreen",
    (document.fullscreenElement || document.webkitFullscreenElement) === skin)
  document.addEventListener("fullscreenchange", onFullscreenChange)
  document.addEventListener("webkitfullscreenchange", onFullscreenChange)
  video.controls = false
  video.autoplay = false
  // Dragging is a preview. Only committing the seek should restart FFmpeg.
  for (const slider of el.querySelector("video-skin").shadowRoot.querySelectorAll("media-time-slider")) {
    slider.pauseOnDrag = false
  }
  const clearInitialLoading = () => skin.removeAttribute("data-initial-loading")
  video.addEventListener("loadeddata", clearInitialLoading)
  let fileId
  return {
    update(data) {
      message.textContent = data.playbackError || ""
      retry.textContent = data.retryLabel || ""
      retry.hidden = !data.retryFileId
      compatible.textContent = data.compatiblePlaybackLabel || ""
      compatible.hidden = data.compatiblePlaybackAvailable !== "true"
      feedback.hidden = !data.playbackError
      // Session changes retain the frame; a different file starts a new opening.
      if (fileId === data.fileId) return
      fileId = data.fileId
      skin.setAttribute("data-initial-loading", "")
    },
    destroy() {
      document.removeEventListener("fullscreenchange", onFullscreenChange)
      document.removeEventListener("webkitfullscreenchange", onFullscreenChange)
      video.removeEventListener("loadeddata", clearInitialLoading)
      retry.removeEventListener("click", onRetry)
      compatible.removeEventListener("click", onCompatible)
    },
  }
}
