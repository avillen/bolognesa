import Hls from "../../vendor/hls.min.mjs"

const CompatibleVideo = {
  mounted() {
    this.sessionId = this.el.dataset.sessionId
    this.offsetMs = Number(this.el.dataset.offsetMs)
    this.durationMs = Number(this.el.dataset.durationMs)
    this.resuming = false
    this.serverPaused = false

    this.currentPosition = () => Math.min(this.durationMs || Infinity,
      this.offsetMs + Math.max(0, Math.floor(this.el.currentTime * 1000)))

    this.el.fileTimeline = {
      offset: this.offsetMs / 1000, duration: this.durationMs / 1000,
      seek: seconds => {
        if (this.el.fileTimeline.pending) return
        this.el.fileTimeline.pending = true
        this.resuming = true
        this.pushEvent("playback_seek", {
          session_id: this.sessionId, position_ms: String(Math.floor(seconds * 1000)),
          playing: String(!this.el.paused),
        })
      },
    }

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

    this.onError = (diagnose = false) => {
      if (!this.serverPaused && !this.resuming) {
        if (diagnose === true) this.reportPlaybackError?.()
        this.pushEvent("compatible_error", {session_id: this.sessionId})
      }
    }
    this.onEnded = () => {
      this.serverPaused = true
      this.hls?.stopLoad()
      this.pushEvent("playback_ended", {session_id: this.sessionId})
    }
    this.el.addEventListener("pause", this.onPause)
    this.el.addEventListener("play", this.onPlay)
    this.el.addEventListener("error", this.onError)
    this.el.addEventListener("ended", this.onEnded)

    if (Hls.isSupported()) {
      this.hls = new Hls({lowLatencyMode: false, liveSyncDurationCount: 1})
      this.hls.on(Hls.Events.MANIFEST_PARSED, () => {
        if (this.el.dataset.autoplay === "true") this.el.play().catch(() => {})
      })
      this.hls.on(Hls.Events.ERROR, (_event, data) => {
        if (data.fatal) this.onError(true)
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
      this.onError(true)
    }
  },
  updated() {
    if (this.el.fileTimeline?.pending) return
    if (this.el.dataset.pausedServer === "true") {
      this.serverPaused = true
      this.el.pause()
    } else {
      this.serverPaused = false
      this.resuming = false
    }
  },
  destroyed() {
    this.el.removeEventListener("pause", this.onPause)
    this.el.removeEventListener("play", this.onPlay)
    this.el.removeEventListener("error", this.onError)
    this.el.removeEventListener("ended", this.onEnded)
    if (this.onNativeReady) this.el.removeEventListener("loadedmetadata", this.onNativeReady)
    this.hls?.destroy()
    delete this.el.fileTimeline
  },
}

export default CompatibleVideo
