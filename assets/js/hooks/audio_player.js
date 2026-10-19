import "../../vendor/videojs.min.mjs"
import AudioError from "./audio_error"

// LiveView owns the frame's data; Video.js owns its children and controls.
export default {
  mounted() {
    this.audio = this.el.querySelector("audio")
    const player = document.createElement("audio-player")
    const skin = document.createElement("audio-skin")
    this.audio.replaceWith(player)
    skin.append(this.audio)
    player.append(skin)
    this.audio.controls = false
    this.context = {el: this.audio, pushEvent: (...args) => this.pushEvent(...args)}
    this.sync = () => {
      const data = this.el.dataset
      Object.assign(this.audio.dataset, {
        generation: data.generation,
        playRequested: data.playRequested,
        stopped: data.stopped,
      })
      this.audio.querySelector("source").setAttribute("src", data.src)
    }
    this.sync()
    AudioError.mounted.call(this.context)
  },
  updated() {
    this.sync()
    AudioError.updated.call(this.context)
  },
  destroyed() {
    AudioError.destroyed.call(this.context)
    this.audio.pause()
    this.audio.querySelector("source").removeAttribute("src")
    this.audio.load()
  },
}
