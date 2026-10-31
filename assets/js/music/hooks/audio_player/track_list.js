export function syncTrackRows(list, snapshot) {
  if (!list || !snapshot) return
  for (const row of list.querySelectorAll("[data-track-id][data-file-id]")) {
    const current = snapshot.selected && row.dataset.trackId === String(snapshot.selected.id) && row.dataset.fileId === String(snapshot.selected.file_id)
    const playing = current && !snapshot.paused && !snapshot.finished
    row.dataset.playback = current ? (playing ? "playing" : "paused") : ""
    const button = row.querySelector(".music-track-play")
    if (button) {
      const label = playing ? button.dataset.pauseLabel : button.dataset.playLabel
      button.setAttribute("aria-label", label)
      button.setAttribute("title", label)
    }
  }
}

export function connectTrackRows(list, session) {
  if (!list || !session) return {sync() {}, destroy() {}}
  let lastSnapshot
  const sync = snapshot => {
    if (snapshot) lastSnapshot = snapshot
    if (lastSnapshot) syncTrackRows(list, lastSnapshot)
  }
  const unsubscribe = session.subscribe(sync)
  const observer = new MutationObserver(() => sync())
  observer.observe(list, {childList: true, subtree: true})
  return {sync, destroy() { unsubscribe(); observer.disconnect() }}
}
