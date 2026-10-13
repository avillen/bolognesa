export default {
  mounted() {
    this.source = this.el.querySelector("source")?.getAttribute("src")
    this.onAudioError = () => this.pushEvent("audio-error", {})
    this.el.addEventListener("error", this.onAudioError, true)
  },
  updated() {
    const source = this.el.querySelector("source")?.getAttribute("src")
    if (source !== this.source) {
      this.source = source
      this.el.load()
    }
  },
  destroyed() {
    this.el.removeEventListener("error", this.onAudioError, true)
  }
}
