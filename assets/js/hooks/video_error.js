const VideoError = {
  mounted() {
    this.reported = false
    this.onError = () => {
      if (this.reported) return
      this.reported = true
      const seconds = this.el.currentTime
      const position = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds * 1000)) : 0
      this.pushEvent("playback_error", {
        file_id: this.el.dataset.fileId, position_ms: String(position),
      })
    }
    this.onEnded = () => this.pushEvent("playback_ended", {file_id: this.el.dataset.fileId})
    this.el.addEventListener("ended", this.onEnded)
    this.el.addEventListener("error", this.onError)
    if (this.el.error) this.onError()
  },
  destroyed() {
    this.el.removeEventListener("ended", this.onEnded)
    this.el.removeEventListener("error", this.onError)
  },
}

export default VideoError
