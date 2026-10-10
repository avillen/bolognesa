import Hls from "../../vendor/hls.min.mjs"

const clock = (ms) => {
  const seconds = Math.floor(ms / 1000)
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`
}

const CompatibleVideo = {
  mounted() {
    this.sessionId = this.el.dataset.sessionId
    this.offsetMs = Number(this.el.dataset.offsetMs)
    this.durationMs = Number(this.el.dataset.durationMs)
    this.seek = document.querySelector(`[data-compatible-seek="${this.sessionId}"]`)
    this.position = document.querySelector(`[data-compatible-position="${this.sessionId}"]`)
    this.resuming = false
    this.serverPaused = false

    this.currentPosition = () => Math.min(this.durationMs || Infinity,
      this.offsetMs + Math.max(0, Math.floor(this.el.currentTime * 1000)))

    this.onTimeUpdate = () => {
      const current = this.currentPosition()
      if (this.seek && document.activeElement !== this.seek) this.seek.value = current
      if (this.position) this.position.textContent = `${clock(current)} / ${clock(this.durationMs)}`
    }

    this.onSeek = () => this.pushEvent("playback_seek", {
      session_id: this.sessionId, position_ms: String(this.seek.value),
      playing: String(!this.el.paused),
    })

    this.onPause = () => {
      if (!this.resuming && !this.el.ended) {
        this.serverPaused = true
        this.pushEvent("playback_pause", {session_id: this.sessionId})
      }
    }

    this.onPlay = () => {
      if (this.serverPaused || this.el.dataset.pausedServer === "true") {
        this.serverPaused = false
        this.resuming = true
        this.pushEvent("playback_resume", {
          session_id: this.sessionId, position_ms: String(this.currentPosition()),
        })
      }
    }

    this.onError = () => {
      if (!this.serverPaused && !this.resuming)
        this.pushEvent("compatible_error", {session_id: this.sessionId})
    }
    this.el.addEventListener("timeupdate", this.onTimeUpdate)
    this.el.addEventListener("pause", this.onPause)
    this.el.addEventListener("play", this.onPlay)
    this.el.addEventListener("error", this.onError)
    if (this.seek) this.seek.addEventListener("change", this.onSeek)
    this.onTimeUpdate()

    if (Hls.isSupported()) {
      this.hls = new Hls({lowLatencyMode: false, liveSyncDurationCount: 1})
      this.hls.on(Hls.Events.MANIFEST_PARSED, () => {
        if (this.el.dataset.autoplay === "true") this.el.play().catch(() => {})
      })
      this.hls.on(Hls.Events.ERROR, (_event, data) => {
        if (data.fatal) this.onError()
      })
      this.hls.loadSource(this.el.dataset.src)
      this.hls.attachMedia(this.el)
    } else if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
      this.el.src = this.el.dataset.src
      this.onNativeReady = () => {
        if (this.el.dataset.autoplay === "true") this.el.play().catch(() => {})
      }
      this.el.addEventListener("loadedmetadata", this.onNativeReady, {once: true})
    } else {
      this.onError()
    }
  },
  updated() {
    if (this.el.dataset.pausedServer === "true") {
      this.serverPaused = true
      this.el.pause()
    } else {
      this.serverPaused = false
      this.resuming = false
    }
  },
  destroyed() {
    this.hls?.destroy()
    this.el.removeEventListener("timeupdate", this.onTimeUpdate)
    this.el.removeEventListener("pause", this.onPause)
    this.el.removeEventListener("play", this.onPlay)
    this.el.removeEventListener("error", this.onError)
    if (this.onNativeReady) this.el.removeEventListener("loadedmetadata", this.onNativeReady)
    if (this.seek) this.seek.removeEventListener("change", this.onSeek)
  },
}

export default CompatibleVideo
