import {connectPlayerDialog} from "./player_dialog.mjs"
import {renderQueue} from "./queue_view.mjs"

const timeLabel = seconds => {
  if (!Number.isFinite(seconds) || seconds < 0) return "--:--"
  const value = Math.floor(seconds)
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, "0")}`
}

export function connectMusicPlayerView(host, session) {
  const player = host.querySelector("#music-player")
  const title = host.querySelector("#now-playing")
  const artist = host.querySelector("[data-player-artist]")
  const album = host.querySelector("[data-player-album]")
  const error = host.querySelector("#audio-error")
  const loading = host.querySelector("[data-player-loading]")
  const seek = host.querySelector('[data-player-action="seek"]')
  const previous = host.querySelector('[data-player-action="previous"]')
  const next = host.querySelector('[data-player-action="next"]')
  const toggle = host.querySelector('[data-player-action="toggle"]')
  const queuePosition = host.querySelector("#queue-position")
  const time = host.querySelector("[data-player-time]")
  const finished = host.querySelector("#queue-finished")
  const queuePanel = host.querySelector("#music-up-next")
  const queueButton = host.querySelector('[data-player-action="queue"]')
  let queueOpen = false
  let queueSnapshot = null
  let upcomingCount = 0
  const setQueueOpen = open => {
    queueOpen = open
    player.dataset.queueOpen = String(open)
    if (queuePanel) queuePanel.hidden = !open
    queueButton?.setAttribute("aria-expanded", String(open))
    if (queueButton) queueButton.textContent = open ? queueButton.dataset.hideLabel : (queueButton.dataset.countLabel || queueButton.dataset.showLabel).replace("__COUNT__", upcomingCount)
  }

  const dialog = connectPlayerDialog(host, {onCollapse: () => setQueueOpen(false)})
  const onClick = event => {
    const button = event.target.closest?.("[data-player-action]")
    const action = button?.dataset.playerAction
    if (action) { const menu = button.closest?.("details"); if (menu) menu.open = false }
    if (action === "previous") session.previous()
    if (action === "next") session.next()
    if (action === "toggle") session.getSnapshot().paused ? session.play() : session.pause()
    if (action === "retry") session.retry()
    if (action === "expand") dialog.expand()
    if (action === "collapse") dialog.collapse(true)
    if (action === "close") session.clear()
    if (action === "queue") setQueueOpen(!queueOpen)
    if (action === "remove-upcoming") {
      session.removeUpcoming(Number(button.dataset.entryId))
      queueButton?.focus()
    }
    if (action === "clear-upcoming") session.clearUpcoming()
    if (action === "move-up" || action === "move-down") {
      const entryId = Number(button.dataset.entryId)
      if (!Number.isSafeInteger(entryId)) return
      session.moveUpcoming(entryId, action === "move-up" ? -1 : 1)
      const moved = queuePanel?.querySelector(`[data-entry-id="${entryId}"]`)
      ;(moved?.closest("details")?.querySelector("summary") || queueButton)?.focus()
    }
  }
  const onInput = event => { if (event.target === seek) session.seek(Number(seek.value)) }
  const onOutsideClick = event => {
    for (const menu of player.querySelectorAll("details[open]")) if (!menu.contains(event.target)) menu.open = false
  }
  player.addEventListener("click", onClick)
  player.addEventListener("input", onInput)
  player.ownerDocument.addEventListener("click", onOutsideClick)
  const observer = typeof ResizeObserver === "function" ? new ResizeObserver(entries => {
    const visible = !host.hidden
    const height = visible ? entries[0]?.contentRect.height : 0
    player.ownerDocument.body.style.setProperty("--music-player-height", `${height || 0}px`)
  }) : null
  observer?.observe(player)
  const render = state => {
    const queueData = JSON.stringify([state.selected, state.queueIndex, state.queue])
    if (queueData !== queueSnapshot) { renderQueue(queuePanel, state); queueSnapshot = queueData }
    const visible = Boolean(state.selected || state.queue.length || state.error || state.loading)
    host.hidden = !visible
    if (!visible) player.ownerDocument.body.style.setProperty("--music-player-height", "0px")
    upcomingCount = Math.max(0, state.queue.length - Math.max(0, state.queueIndex + 1))
    if (!queueOpen) setQueueOpen(false)
    renderTrack(state)
    renderControls(state)
    renderStatus(state)
    renderSeek(state)
  }
  const renderTrack = state => {
    title.textContent = state.selected?.title || ""
    artist.textContent = state.selected?.artist || ""
    if (album) album.textContent = state.selected?.album || ""
  }
  const renderControls = state => {
    const canPrevious = Boolean(state.selected) || state.queueIndex > 0
    const canNext = state.queueIndex >= 0 && state.queueIndex < state.queueCount - 1
    previous.disabled = !canPrevious
    next.disabled = !canNext
    const toggleLabel = state.paused ? toggle.dataset.labelPlay : toggle.dataset.labelPause
    toggle.setAttribute("aria-label", toggleLabel)
    toggle.setAttribute("title", toggleLabel)
    const playIcon = toggle.querySelector("[data-player-play-icon]")
    const pauseIcon = toggle.querySelector("[data-player-pause-icon]")
    if (playIcon) playIcon.hidden = !state.paused
    if (pauseIcon) pauseIcon.hidden = state.paused
    queuePosition.textContent = state.queueCount && state.queueIndex >= 0 ? `${state.queueIndex + 1} / ${state.queueCount}` : ""
    const elapsed = time.querySelector("[data-player-elapsed]")
    const duration = time.querySelector("[data-player-duration]")
    if (elapsed && duration) { elapsed.textContent = timeLabel(state.position); duration.textContent = timeLabel(state.duration) }
    else time.textContent = `${timeLabel(state.position)} / ${timeLabel(state.duration)}`
  }
  const renderStatus = state => {
    finished.hidden = !state.finished
    const message = state.error && host.querySelector(`[data-player-error="${state.error.code}"]`)
    loading.hidden = !state.loading
    error.textContent = message?.textContent || ""
    error.hidden = !state.error || !message
    player.querySelector('[data-player-action="retry"]').hidden = !state.error?.retryable
  }
  const renderSeek = state => {
    seek.disabled = !Number.isFinite(state.duration) || state.duration <= 0
    seek.max = state.duration || 100
    seek.value = state.position || 0
    const progress = state.duration > 0 ? Math.max(0, Math.min(100, 100 * state.position / state.duration)) : 0
    seek.style?.setProperty("--music-progress", `${progress}%`)
    seek.setAttribute("aria-valuetext", `${timeLabel(state.position)} / ${timeLabel(state.duration)}`)
  }
  const unsubscribe = session.subscribe(render)

  return {destroy() {
    dialog.destroy(); unsubscribe(); observer?.disconnect()
    player.removeEventListener("click", onClick); player.removeEventListener("input", onInput)
    player.ownerDocument.removeEventListener("click", onOutsideClick)
    player.ownerDocument.body.style.removeProperty("--music-player-height")
  }}
}
