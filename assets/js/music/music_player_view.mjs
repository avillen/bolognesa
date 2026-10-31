const timeLabel = seconds => {
  if (!Number.isFinite(seconds) || seconds < 0) return "--:--"
  const value = Math.floor(seconds)
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, "0")}`
}

export function connectMusicPlayerView(host, session) {
  const player = host.querySelector("#music-player")
  const title = host.querySelector("#now-playing")
  const artist = host.querySelector("[data-player-artist]")
  const error = host.querySelector("#audio-error")
  const loading = host.querySelector("[data-player-loading]")
  const seek = host.querySelector('[data-player-action="seek"]')
  const previous = host.querySelector('[data-player-action="previous"]')
  const next = host.querySelector('[data-player-action="next"]')
  const toggle = host.querySelector('[data-player-action="toggle"]')
  const queuePosition = host.querySelector("#queue-position")
  const time = host.querySelector("[data-player-time]")
  const finished = host.querySelector("#queue-finished")
  let inertElements = null
  let expanded = false
  let previousFocus = null

  const collapse = restoreFocus => {
    if (!expanded) return
    expanded = false
    player.dataset.expanded = "false"
    player.setAttribute("role", "region")
    player.removeAttribute("aria-modal")
    inertElements?.forEach(([element, wasInert]) => { element.inert = wasInert })
    inertElements = null
    if (restoreFocus) (previousFocus?.isConnected ? previousFocus : host.querySelector('[data-player-action="expand"]'))?.focus()
    previousFocus = null
  }
  const expand = () => {
    if (expanded) return
    expanded = true
    previousFocus = host.querySelector('[data-player-action="expand"]')
    player.dataset.expanded = "true"
    player.setAttribute("role", "dialog")
    player.setAttribute("aria-modal", "true")
    inertElements = []
    let branch = host
    while (branch.parentElement) {
      const parent = branch.parentElement
      for (const element of parent.children) if (element !== branch) inertElements.push([element, element.inert])
      if (parent === host.ownerDocument.body) break
      branch = parent
    }
    inertElements.forEach(([element]) => { element.inert = true })
    host.querySelector('[data-player-action="collapse"]')?.focus()
  }
  const onClick = event => {
    const action = event.target.closest?.("[data-player-action]")?.dataset.playerAction
    if (action === "previous") session.previous()
    if (action === "next") session.next()
    if (action === "toggle") session.getSnapshot().paused ? session.play() : session.pause()
    if (action === "retry") session.retry()
    if (action === "expand") expand()
    if (action === "collapse") collapse(true)
  }
  const onInput = event => { if (event.target === seek) session.seek(Number(seek.value)) }
  const onKeydown = event => {
    if (event.key === "Escape" && expanded) { event.preventDefault(); collapse(true); return }
    if (event.key !== "Tab" || !expanded) return
    const focusable = [...player.querySelectorAll('button:not([disabled]):not([hidden]), input:not([disabled]):not([hidden]), a[href]')]
    if (!focusable.length) return
    const first = focusable[0], last = focusable[focusable.length - 1]
    if (event.shiftKey && player.ownerDocument.activeElement === first) { event.preventDefault(); last.focus() }
    else if (!event.shiftKey && player.ownerDocument.activeElement === last) { event.preventDefault(); first.focus() }
  }
  const onPageLoading = () => collapse(false)
  player.addEventListener("click", onClick)
  player.addEventListener("input", onInput)
  player.ownerDocument.addEventListener("keydown", onKeydown)
  player.ownerDocument.defaultView?.addEventListener("phx:page-loading-start", onPageLoading)
  const observer = typeof ResizeObserver === "function" ? new ResizeObserver(entries => {
    const visible = !host.hidden
    const height = visible ? entries[0]?.contentRect.height : 0
    player.ownerDocument.body.style.setProperty("--music-player-height", `${height || 0}px`)
  }) : null
  observer?.observe(player)
  const unsubscribe = session.subscribe(state => {
    const visible = Boolean(state.selected || state.queue.length || state.error || state.loading)
    host.hidden = !visible
    if (!visible) player.ownerDocument.body.style.setProperty("--music-player-height", "0px")
    host.querySelector('[data-player-action="expand"]').hidden = expanded
    host.querySelector('[data-player-action="collapse"]').hidden = !expanded
    title.textContent = state.selected?.title || ""
    artist.textContent = state.selected?.artist || ""
    const canPrevious = state.queueIndex > 0
    const canNext = state.queueIndex >= 0 && state.queueIndex < state.queueCount - 1
    previous.disabled = !canPrevious
    next.disabled = !canNext
    toggle.textContent = state.paused ? toggle.dataset.labelPlay : toggle.dataset.labelPause
    toggle.setAttribute("aria-label", toggle.textContent)
    queuePosition.textContent = state.queueCount && state.queueIndex >= 0 ? `${state.queueIndex + 1} / ${state.queueCount}` : ""
    time.textContent = `${timeLabel(state.position)} / ${timeLabel(state.duration)}`
    finished.hidden = !state.finished
    const message = state.error && host.querySelector(`[data-player-error="${state.error.code}"]`)
    loading.hidden = !state.loading
    error.textContent = message?.textContent || ""
    error.hidden = !state.error || !message
    player.querySelector('[data-player-action="retry"]').hidden = !state.error?.retryable
    seek.disabled = !Number.isFinite(state.duration) || state.duration <= 0
    seek.max = state.duration || 100
    seek.value = state.position || 0
    seek.setAttribute("aria-valuetext", `${timeLabel(state.position)} / ${timeLabel(state.duration)}`)
  })
  return {destroy() {
    collapse(false); unsubscribe(); observer?.disconnect()
    player.removeEventListener("click", onClick); player.removeEventListener("input", onInput)
    player.ownerDocument.removeEventListener("keydown", onKeydown)
    player.ownerDocument.defaultView?.removeEventListener("phx:page-loading-start", onPageLoading)
    player.ownerDocument.body.style.removeProperty("--music-player-height")
  }}
}
