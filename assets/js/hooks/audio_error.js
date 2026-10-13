function syncPlayback(hook, reload) {
  const generation = hook.el.dataset?.generation
  if (hook.el.dataset?.stopped === "true") hook.el.pause()
  if (generation === hook.generation && !reload) return
  hook.generation = generation
  if (reload) hook.el.load()
  if (hook.el.dataset?.playRequested !== "true" || hook.el.dataset?.stopped === "true") return
  hook.el.play().catch(error => {
    if (hook.generation !== generation || hook.destroyedFlag || error.name === "AbortError") return
    hook.pushEvent(error.name === "NotAllowedError" ? "audio-blocked" : "audio-error", {generation})
  })
}

export default {
  mounted() {
    this.source = this.el.querySelector("source")?.getAttribute("src")
    this.onAudioError = () => this.pushEvent("audio-error", {generation: this.el.dataset?.generation})
    this.onEnded = () => this.pushEvent("audio-ended", {generation: this.el.dataset?.generation})
    this.el.addEventListener("error", this.onAudioError, true)
    this.el.addEventListener("ended", this.onEnded)
    syncPlayback(this, false)
  },
  updated() {
    const source = this.el.querySelector("source")?.getAttribute("src")
    const reload = source !== this.source || this.el.dataset?.generation !== this.generation
    this.source = source
    syncPlayback(this, reload)
  },
  destroyed() {
    this.destroyedFlag = true
    this.el.removeEventListener("error", this.onAudioError, true)
    this.el.removeEventListener("ended", this.onEnded)
  }
}
