const VideoError = {
  mounted() {
    this.onError = () => this.pushEvent("playback_error", {file_id: this.el.dataset.fileId})
    this.el.addEventListener("error", this.onError)
  },
  destroyed() {
    this.el.removeEventListener("error", this.onError)
  },
}

export default VideoError
