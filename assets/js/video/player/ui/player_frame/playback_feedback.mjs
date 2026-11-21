/** Builds the playback error message with its retry and compatible-playback actions. */
export function createPlaybackFeedback({el, pushEvent}) {
  const document = el.ownerDocument
  const element = document.createElement("div")
  element.className = "bolognesa-playback-feedback"
  element.setAttribute("role", "alert")
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
  element.append(message, retry, compatible)
  return {
    element,
    update(data) {
      message.textContent = data.playbackError || ""
      retry.textContent = data.retryLabel || ""
      retry.hidden = !data.retryFileId
      compatible.textContent = data.compatiblePlaybackLabel || ""
      compatible.hidden = data.compatiblePlaybackAvailable !== "true"
      element.hidden = !data.playbackError
    },
    destroy() {
      retry.removeEventListener("click", onRetry)
      compatible.removeEventListener("click", onCompatible)
    },
  }
}
