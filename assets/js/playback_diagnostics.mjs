let tabId
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
function correlationId() {
  // getRandomValues works on HTTP LAN origins; this identifier never authorizes access.
  const bytes = new Uint8Array(16)
  if (globalThis.crypto?.getRandomValues) globalThis.crypto.getRandomValues(bytes)
  else for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256)
  bytes[6] = (bytes[6] & 15) | 64
  bytes[8] = (bytes[8] & 63) | 128
  const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("")
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}
function currentTabId() {
  if (tabId) return tabId
  try {
    const stored = sessionStorage.getItem("bolognesa.playback.tab")
    tabId = uuidPattern.test(stored || "") ? stored : correlationId()
    sessionStorage.setItem("bolognesa.playback.tab", tabId)
  } catch {
    tabId ||= correlationId()
  }
  return tabId
}

// Observations only: never control playback or retry delivery on behalf of the player.
export function createPlaybackDiagnostics(hook, doc = document) {
  let connected = true
  let sequence = 0
  const pending = []
  let stall = null
  const sourceKey = () => `${hook.el.dataset.fileId}:${hook.el.dataset.sessionId || ""}`
  const bufferedMs = () => {
    const {video} = hook
    for (let i = 0; i < (video.buffered?.length || 0); i++) {
      if (video.buffered.start(i) <= video.currentTime && video.currentTime <= video.buffered.end(i)) {
        return Math.max(0, Math.min(2147483647, Math.floor((video.buffered.end(i) - video.currentTime) * 1000)))
      }
    }
    return 0
  }
  const report = (diagnostic, stallDurationMs = 0) => {
    const {video, el} = hook
    if (!el.dataset.fileId) return
    const position = (video.fileTimeline?.offset || 0) + (video.currentTime || 0)
    const payload = {
      diagnostic, tab_id: currentTabId(), session_id: el.dataset.sessionId || null,
      file_id: el.dataset.fileId, sequence: ++sequence, client_time_ms: Date.now(),
      position_ms: Number.isFinite(position) ? Math.max(0, Math.min(2147483647, Math.floor(position * 1000))) : 0,
      buffered_ms: bufferedMs(), stall_duration_ms: stallDurationMs,
      paused: video.paused, visibility: doc.visibilityState === "hidden" ? "hidden" : "visible",
      media_error: [1, 2, 3, 4].includes(video.error?.code) ? video.error.code : 0,
    }
    if (connected) hook.pushEvent("playback_diagnostic", payload)
    else if (pending.length < 8) pending.push(payload)
  }
  const visibility = () => report("visibility")
  const error = () => report("error")
  const waiting = () => {
    if (hook.video.paused || hook.video.ended) return
    const key = sourceKey()
    if (stall?.key === key) return
    stall = {key, started: performance.now()}
    report("waiting")
  }
  const playing = () => {
    if (stall?.key === sourceKey()) {
      report("recovered", Math.max(0, Math.min(2147483647, Math.floor(performance.now() - stall.started))))
    }
    stall = null
  }
  const resetStall = () => { stall = null }
  hook.video.addEventListener("waiting", waiting)
  hook.video.addEventListener("playing", playing)
  hook.video.addEventListener("emptied", resetStall)
  hook.video.addEventListener("pause", resetStall)
  doc.addEventListener("visibilitychange", visibility)
  hook.video.addEventListener("error", error)
  report("mounted")
  if (hook.video.error) report("error")
  return {
    reportError: error,
    disconnected() {
      if (!connected) return
      connected = false
      report("disconnected")
    },
    reconnected() {
      connected = true
      for (const payload of pending.splice(0)) hook.pushEvent("playback_diagnostic", payload)
      report("reconnected")
    },
    destroy() {
      doc.removeEventListener("visibilitychange", visibility)
      hook.video.removeEventListener("error", error)
      hook.video.removeEventListener("waiting", waiting)
      hook.video.removeEventListener("playing", playing)
      hook.video.removeEventListener("emptied", resetStall)
      hook.video.removeEventListener("pause", resetStall)
      pending.length = 0
    },
  }
}
