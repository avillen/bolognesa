// The skin's own hotkeys only listen while the player has focus; these also work from the rest of the page.
const playerHotkeys = [
  ["Space", "togglePaused"], ["k", "togglePaused"], ["m", "toggleMuted"], ["f", "toggleFullscreen"],
  ["c", "toggleSubtitles"], ["i", "togglePictureInPicture"],
  ["ArrowLeft", "seekStep"], ["ArrowRight", "seekStep"], ["j", "seekStep"], ["l", "seekStep"],
  ["ArrowUp", "volumeStep"], ["ArrowDown", "volumeStep"], [">", "speedUp"], ["<", "speedDown"],
  ["0-9", "seekToPercent"], ["Home", "seekToPercent", 0], ["End", "seekToPercent", 100], ["p", "seekToPercent", 0],
]

// Within this many seconds, "p" goes to the previous entry instead of restarting the current one.
export const restartThreshold = 3

/** Returns the id of the entry link a key opens, or null when Video.js should handle the key. */
export function entryLinkId(key, position) {
  if (key === "n") return "episode-next"
  if (key === "p" && position < restartThreshold) return "episode-previous"
  return null
}

/** Binds player hotkeys to the whole page and "n"/"p" to the episode navigation links. */
export function connectPageHotkeys({skin, video}) {
  const document = skin.ownerDocument
  for (const [keys, action, value] of playerHotkeys) {
    const hotkey = document.createElement("media-hotkey")
    Object.assign(hotkey, {keys, action, value, target: "document"})
    skin.append(hotkey)
  }
  // Captures before Video.js so a handled entry key never also restarts playback.
  const onKeydown = event => {
    if (event.defaultPrevented || event.repeat || event.ctrlKey || event.metaKey || event.altKey ||
      event.target.closest?.("input, textarea, select, [contenteditable]")) return
    const id = entryLinkId(event.key, (video.fileTimeline?.offset || 0) + video.currentTime)
    const link = id && document.getElementById(id)
    if (!link) return
    event.preventDefault()
    link.click()
  }
  document.addEventListener("keydown", onKeydown, {capture: true})
  return () => document.removeEventListener("keydown", onKeydown, {capture: true})
}
