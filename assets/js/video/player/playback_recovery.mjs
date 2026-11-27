const storageKey = "bolognesa.playback.checkpoint"
const lifetimeMs = 12 * 60 * 60 * 1000

function browserStorage() {
  try { return sessionStorage } catch { return null }
}

// One checkpoint per tab. Stored values are hints; the server validates HLS start offsets.
export function createPlaybackRecovery(hook, storage = browserStorage()) {
  const {video, el} = hook
  let fileId, scope, pending, active = false, complete = false, lastSaved = 0
  const remove = () => { try { storage?.removeItem(storageKey) } catch {} }
  const read = () => {
    try {
      const point = JSON.parse(storage?.getItem(storageKey) || "null")
      if (el.dataset.recoveryScope && point?.scope === el.dataset.recoveryScope &&
          point.fileId === el.dataset.fileId && Number.isInteger(point.positionMs) &&
          point.positionMs >= 0 && point.positionMs <= 2147483647 && typeof point.paused === "boolean" &&
          Number.isFinite(point.savedAt) && Date.now() >= point.savedAt && Date.now() - point.savedAt < lifetimeMs) return point
    } catch {}
    return null
  }
  const save = () => {
    if (!active || pending || complete || !scope || video.ended || video.error) return
    const positionMs = Math.floor(((video.fileTimeline?.offset || 0) + video.currentTime) * 1000)
    if (!Number.isFinite(positionMs) || positionMs < 0 || positionMs > 2147483647) return
    try {
      storage?.setItem(storageKey, JSON.stringify({scope,
        fileId, positionMs, paused: video.paused, savedAt: Date.now()}))
      lastSaved = Date.now()
    } catch {}
  }
  const progress = () => { if (Date.now() - lastSaved >= 3000) save() }
  const ended = () => { complete = true; pending = null; remove() }
  const play = () => { complete = false; save() }
  const listeners = {timeupdate: progress, seeked: save, pause: save, play, ended}
  for (const [name, handler] of Object.entries(listeners)) video.addEventListener(name, handler)

  return {
    /** Optional start hint sent with the capability report; the server validates it. */
    initial() {
      const point = read()
      return point && {position_ms: point.positionMs, paused: point.paused}
    },
    suspend() { active = false },
    beforeSourceChange() { save(); active = false },
    source({retry = false} = {}) {
      if (retry || fileId !== el.dataset.fileId || scope !== el.dataset.recoveryScope) {
        scope = el.dataset.recoveryScope
        fileId = el.dataset.fileId
        pending = read()
        complete = false
      }
      if (!el.dataset.src) return false
      if (pending && el.dataset.sessionId) {
        const duration = Number(el.dataset.durationMs)
        if (duration > 0 && pending.positionMs >= duration) { pending = null; remove() }
        // The server prepared HLS at the checkpoint sent with the capability report; another offset means it refused the hint.
        else if (Math.abs(Number(el.dataset.offsetMs) - pending.positionMs) > 1000) {
          pending = null
          hook.diagnostics?.report("restore_failed")
        }
      }
      return true
    },
    ready() {
      const point = pending
      let restored = false
      const autoplay = point ? !point.paused : el.dataset.autoplay === "true"
      if (point && !el.dataset.sessionId) {
        if (!Number.isFinite(video.duration) || point.positionMs / 1000 >= video.duration) {
          pending = null
          remove()
        } else {
          try { video.currentTime = point.positionMs / 1000; restored = true }
          catch { hook.diagnostics?.report("restore_failed") }
        }
      } else restored = !!point
      pending = null
      active = true
      if (restored) hook.diagnostics?.report("restored")
      if (autoplay) video.play().catch(() => hook.diagnostics?.report("autoplay_blocked"))
      else video.pause()
    },
    save,
    destroy() {
      save()
      for (const [name, handler] of Object.entries(listeners)) video.removeEventListener(name, handler)
    },
  }
}
