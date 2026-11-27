import {getBrowserRuntime} from "../../browser_runtime.mjs"
import {createPlayer, videoFeatures, timeFeature, bufferFeature} from "../../../vendor/videojs.min.mjs"
import {fileTimeFeature, fileBufferFeature} from "../player/timeline.mjs"
import {createPlaybackDiagnostics} from "../player/playback_diagnostics.mjs"
import {createPlaybackRecovery} from "../player/playback_recovery.mjs"
import {createWatchedPlayback} from "../player/watched_playback.mjs"
import Hls from "../../../vendor/hls.min.mjs"
import {probePlaybackCapabilities} from "../player/playback_capabilities.mjs"
import {createSourceController} from "../player/source_controller.mjs"
import {createPlayerFrame} from "../player/ui/player_frame.mjs"

const {PlayerElement} = createPlayer({features: videoFeatures.map(feature => {
  if (feature === timeFeature) return fileTimeFeature(feature)
  if (feature === bufferFeature) return fileBufferFeature(feature)
  return feature
})})
customElements.define("bolognesa-video-player", PlayerElement)

const VideoPlayer = {
  mounted() {
    this.video = this.el.querySelector("video")
    this.unregisterMedia = getBrowserRuntime()?.mediaCoordinator.register(this.video)
    this.frame = createPlayerFrame({el: this.el, video: this.video, pushEvent: (...args) => this.pushEvent(...args)})
    this.recovery = createPlaybackRecovery(this)
    this.scope = this.el.dataset.recoveryScope
    this.diagnostics = createPlaybackDiagnostics(this)
    this.watched = createWatchedPlayback({video: this.video, report: report => new Promise((resolve, reject) => {
      this.pushEvent("record_watched_entries", report, reply => reply.ok ? resolve() : reject(new Error("watched recording failed")))
    })})
    this.sources = createSourceController(this, {Hls})
    this.sync = () => {
      const data = this.el.dataset
      this.frame.update(data)
      if (this.scope !== data.recoveryScope) {
        this.diagnostics.destroy()
        this.scope = data.recoveryScope
        this.diagnostics = createPlaybackDiagnostics(this)
      }
      this.watched.update({...data})
      this.sources.update()
      if (data.playbackPhase === "checking" && data.playbackProbe) {
        const probe = JSON.parse(data.playbackProbe)
        if (this.probeGeneration !== probe.generation) {
          this.probeGeneration = probe.generation
          probePlaybackCapabilities(probe, {video: this.video, Hls}).then(report => {
            if (this.probeDestroyed || this.el.dataset.playbackPhase !== "checking" ||
                this.probeGeneration !== report.generation) return
            const initial = this.recovery.initial()
            this.pushEvent("playback_capabilities", initial ? {...report, initial} : report)
          })
        }
      } else this.probeGeneration = null
    }
    this.retrySource = () => this.sources.retry()
    this.sync()
  },
  updated() { this.sync() },
  disconnected() { this.diagnostics?.disconnected() },
  reconnected() { this.diagnostics?.reconnected() },
  destroyed() {
    this.probeDestroyed = true
    this.unregisterMedia?.()
    this.unregisterMedia = null
    this.recovery?.destroy()
    this.diagnostics?.destroy()
    this.watched?.destroy()
    this.sources?.destroy()
    this.frame?.destroy()
  },
}

export default VideoPlayer
