// Rows are streamed independently of the player. Reconcile after list patches too.
export function syncTrackRows(list, audio, source) {
  for (const row of list.querySelectorAll("[data-track-src]")) {
    const current = row.dataset.trackSrc === source && !audio.ended && !audio.error
    const playing = current && !audio.paused
    row.dataset.playback = current ? (playing ? "playing" : "paused") : ""
    const button = row.querySelector(".music-track-play")
    if (button) button.setAttribute("aria-label", playing ? button.dataset.pauseLabel : button.dataset.playLabel)
  }
}

export function connectTrackRows(frame, audio, pushEvent) {
  const list = frame.closest?.(".music-library")?.querySelector("#music-tracks")
  if (!list) return {sync() {}, destroy() {}}
  let destroyed = false
  const sync = () => syncTrackRows(list, audio, frame.dataset.src)
  const events = ["playing", "pause", "ended", "error", "emptied"]
  for (const event of events) audio.addEventListener(event, sync)
  const observer = new MutationObserver(sync)
  observer.observe(list, {childList: true, subtree: true})
  const click = event => {
    const button = event.target.closest(".music-track-play")
    if (!button || button.closest("[data-track-src]")?.dataset.trackSrc !== frame.dataset.src) return
    event.preventDefault()
    event.stopImmediatePropagation()
    if (!audio.paused && !audio.ended) audio.pause()
    else {
      const generation = frame.dataset.generation
      audio.play().catch(error => {
        if (!destroyed && generation === frame.dataset.generation && error.name !== "AbortError") {
          pushEvent(error.name === "NotAllowedError" ? "audio-blocked" : "audio-error", {generation})
        }
      })
    }
  }
  list.addEventListener("click", click, true)
  sync()
  return {
    sync,
    destroy() {
      destroyed = true
      observer.disconnect()
      list.removeEventListener("click", click, true)
      for (const event of events) audio.removeEventListener(event, sync)
    },
  }
}
