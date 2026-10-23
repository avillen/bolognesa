let tabId
let pageId
let pageSequence = 0
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

function browserStorage() { try { return sessionStorage } catch { return null } }

function readHistory(storage, scope, fileId) {
  try {
    const saved = JSON.parse(storage?.getItem("bolognesa.playback.diagnostics") || "null")
    if (!scope || !saved) return []
    // History belongs to one viewer/content/file, just like the recovery checkpoint.
    if (saved.scope !== scope || saved.fileId !== fileId) return []
    const age = Date.now() - saved.savedAt
    if (!Number.isFinite(age) || age < 0 || age >= 12 * 60 * 60 * 1000) return []
    if (!Array.isArray(saved.events)) return []
    return saved.events.slice(-8).filter(event => uuidPattern.test(event?.page_id || "") && Number.isInteger(event.sequence))
  } catch { return [] }
}

// Observations only: never retry delivery on behalf of the player.
export function createPlaybackDiagnostics(hook, doc = document, win = globalThis.window, storage = browserStorage()) {
  let connected = true
  const pending = []
  let stall = null
  let destroyed = false
  pageId ||= correlationId()
  const storageKey = "bolognesa.playback.diagnostics"
  const scope = hook.el.dataset.recoveryScope
  let unacknowledged = readHistory(storage, scope, hook.el.dataset.fileId)
  const persist = () => {
    try {
      if (scope) storage?.setItem(storageKey, JSON.stringify({scope, fileId: hook.el.dataset.fileId,
        savedAt: Date.now(), events: unacknowledged}))
    } catch {}
  }
  const send = payload => {
    try {
      hook.pushEvent("playback_diagnostic", payload, () => {
        if (destroyed) return
        unacknowledged = unacknowledged.filter(x => x.page_id !== payload.page_id || x.sequence !== payload.sequence)
        persist()
      })
    } catch {} // A tearing-down LiveView may no longer accept pushes; retain the observation.
  }
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
  const report = (diagnostic, stallDurationMs = 0, extra = {}) => {
    const {video, el} = hook
    if (destroyed || !el.dataset.fileId) return
    const position = (video.fileTimeline?.offset || 0) + (video.currentTime || 0)
    const payload = {
      diagnostic, tab_id: currentTabId(), session_id: el.dataset.sessionId || null,
      page_id: pageId, replayed: false,
      file_id: el.dataset.fileId, sequence: ++pageSequence, client_time_ms: Date.now(),
      position_ms: Number.isFinite(position) ? Math.max(0, Math.min(2147483647, Math.floor(position * 1000))) : 0,
      buffered_ms: bufferedMs(), stall_duration_ms: stallDurationMs,
      paused: video.paused, visibility: doc.visibilityState === "hidden" ? "hidden" : "visible",
      media_error: [1, 2, 3, 4].includes(video.error?.code) ? video.error.code : 0,
      ready_state: [0, 1, 2, 3, 4].includes(video.readyState) ? video.readyState : 0,
      network_state: [0, 1, 2, 3].includes(video.networkState) ? video.networkState : 0,
      online: win?.navigator?.onLine !== false,
      navigation_type: ["navigate", "reload", "back_forward"].includes(win?.performance?.getEntriesByType?.("navigation")?.[0]?.type)
        ? win.performance.getEntriesByType("navigation")[0].type : "unknown",
      ws_code: Number.isInteger(extra.ws_code) && extra.ws_code >= 1000 && extra.ws_code <= 4999 ? extra.ws_code : 0,
      ws_clean: extra.ws_clean === true,
    }
    unacknowledged.push(payload)
    unacknowledged = unacknowledged.slice(-8)
    persist()
    if (connected) send(payload)
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
  const pageListeners = Object.fromEntries(["pagehide", "pageshow", "online", "offline"].map(name =>
    [name, () => { hook.recovery?.save(); report(name) }]))
  const transport = event => {
    if (["socket_open", "socket_closed", "socket_error"].includes(event.detail?.diagnostic)) {
      report(event.detail.diagnostic, 0, event.detail)
    }
  }
  for (const [name, handler] of Object.entries(pageListeners)) win?.addEventListener(name, handler)
  win?.addEventListener("bolognesa:transport", transport)
  const timer = setInterval(() => { if (!hook.video.paused && !hook.video.ended) report("progress") }, 30000)
  timer.unref?.()
  for (const payload of [...unacknowledged]) send({...payload, replayed: true})
  report("mounted")
  if (hook.video.error) report("error")
  return {
    report,
    reportError: error,
    disconnected() {
      if (!connected) return
      connected = false
      report("disconnected")
    },
    reconnected() {
      connected = true
      for (const payload of pending.splice(0)) send(payload)
      report("reconnected")
    },
    destroy() {
      report("destroyed")
      destroyed = true
      clearInterval(timer)
      for (const [name, handler] of Object.entries(pageListeners)) win?.removeEventListener(name, handler)
      win?.removeEventListener("bolognesa:transport", transport)
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
