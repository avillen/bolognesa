import "../../vendor/videojs.min.mjs"
import AudioError from "./audio_error"
import {connectTrackRows} from "./audio_track_list"

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
    this.trackRows = connectTrackRows(this.el, this.audio, (...args) => this.pushEvent(...args))
  },
  updated() {
    this.sync()
    AudioError.updated.call(this.context)
    this.trackRows.sync()
  },
  destroyed() {
    this.trackRows.destroy()
    AudioError.destroyed.call(this.context)
    this.audio.pause()
    this.audio.querySelector("source").removeAttribute("src")
    this.audio.load()
  },
}
