import {createPlayer, videoFeatures, timeFeature, bufferFeature} from "../../../vendor/videojs.min.mjs"
import {fileTimeFeature, fileBufferFeature} from "./video_player/timeline.mjs"
import {createPlaybackDiagnostics} from "./video_player/playback_diagnostics.mjs"
import {createPlaybackRecovery} from "./video_player/playback_recovery.mjs"
import Hls from "../../../vendor/hls.min.mjs"
import {createSourceController} from "./video_player/source_controller.mjs"
import {createPlayerFrame} from "./video_player/player_frame.mjs"

const {PlayerElement} = createPlayer({features: videoFeatures.map(feature => {
  if (feature === timeFeature) return fileTimeFeature(feature)
  if (feature === bufferFeature) return fileBufferFeature(feature)
  return feature
})})
customElements.define("bolognesa-video-player", PlayerElement)

const VideoPlayer = {
  mounted() {
    this.video = this.el.querySelector("video")
    this.unregisterMedia = window.bolognesaMusicPlayer?.coordinator.register(this.video)
    this.frame = createPlayerFrame({el: this.el, video: this.video, pushEvent: (...args) => this.pushEvent(...args)})
    this.recovery = createPlaybackRecovery(this)
    this.scope = this.el.dataset.recoveryScope
    this.diagnostics = createPlaybackDiagnostics(this)
    this.sources = createSourceController(this, {Hls})
    this.sync = () => {
      const data = this.el.dataset
      this.frame.update(data)
      if (this.scope !== data.recoveryScope) {
        this.diagnostics.destroy()
        this.scope = data.recoveryScope
        this.diagnostics = createPlaybackDiagnostics(this)
      }
      this.sources.update()
    }
    this.retrySource = () => this.sources.retry()
    this.sync()
  },
  updated() { this.sync() },
  disconnected() { this.diagnostics?.disconnected() },
  reconnected() { this.diagnostics?.reconnected() },
  destroyed() {
    this.unregisterMedia?.()
    this.unregisterMedia = null
    this.recovery?.destroy()
    this.diagnostics?.destroy()
    this.sources?.destroy()
    this.frame?.destroy()
  },
}

export default VideoPlayer
