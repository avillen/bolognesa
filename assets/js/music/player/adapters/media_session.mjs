export function connectMediaSession(window, audio, session) {
  const mediaSession = window?.navigator?.mediaSession
  const Metadata = window?.MediaMetadata
  const actions = {play: () => session.play(), pause: () => session.pause(), previoustrack: () => session.previous(), nexttrack: () => session.next()}
  const registered = new Map()
  let ownsControls = false
  let selectedKey = null

  function updateActions({selected, queueIndex, queueCount}) {
    const enabled = {
      play: ownsControls,
      pause: ownsControls,
      previoustrack: ownsControls && (Boolean(selected) || queueIndex > 0),
      nexttrack: ownsControls && queueIndex >= 0 && queueIndex < queueCount - 1,
    }
    for (const [action, handler] of Object.entries(actions)) {
      if (registered.get(action) === enabled[action]) continue
      try { mediaSession?.setActionHandler?.(action, enabled[action] ? handler : null) } catch (_) { /* Unsupported action. */ }
      registered.set(action, enabled[action])
    }
  }

  function setActive(enabled) {
    ownsControls = enabled
    updateActions(session.getSnapshot())
    if (mediaSession) mediaSession.playbackState = enabled ? (audio.paused ? "paused" : "playing") : "none"
  }

  const unsubscribe = session.subscribe(({selected, paused, queueIndex, queueCount}) => {
    if (!mediaSession) return
    if (ownsControls) updateActions({selected, queueIndex, queueCount})
    if (ownsControls) mediaSession.playbackState = selected ? (paused ? "paused" : "playing") : "none"
    if (!Metadata) return
    const key = selected ? JSON.stringify([selected.id, selected.file_id, selected.title, selected.artist, selected.album]) : null
    if (key === selectedKey) return
    selectedKey = key
    mediaSession.metadata = selected ? new Metadata({title: selected.title || "", artist: selected.artist || "", album: selected.album || "", artwork: [{src: "/images/bolognesa-cat.svg", type: "image/svg+xml"}]}) : null
  })

  return {setActive, destroy() { unsubscribe(); if (ownsControls) setActive(false) }}
}
