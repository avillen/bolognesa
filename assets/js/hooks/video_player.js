import {createPlayer, videoFeatures, timeFeature, bufferFeature} from "../../vendor/videojs.min.mjs"
import {fileTimeFeature, fileBufferFeature} from "../video_timeline.mjs"
import {createPlaybackDiagnostics} from "../playback_diagnostics.mjs"
import VideoError from "./video_error"
import TranscodeVideo from "./transcode_video"

const {PlayerElement} = createPlayer({features: videoFeatures.map(feature => {
  if (feature === timeFeature) return fileTimeFeature(feature)
  if (feature === bufferFeature) return fileBufferFeature(feature)
  return feature
})})
customElements.define("bolognesa-video-player", PlayerElement)

const VideoPlayer = {
  mounted() {
    this.video = this.el.querySelector("video")
    // Connect the player before its skin so all controls find the player's context.
    const player = document.createElement("bolognesa-video-player")
    const skin = document.createElement("video-skin")
    this.video.replaceWith(player)
    skin.append(this.video)
    player.append(skin)
    this.video.controls = false
    this.video.autoplay = false
    // Dragging is a preview. Only committing the seek should restart FFmpeg.
    for (const slider of this.el.querySelector("video-skin").shadowRoot.querySelectorAll("media-time-slider")) {
      slider.pauseOnDrag = false
    }
    this.clearInitialLoading = () => skin.removeAttribute("data-initial-loading")
    this.video.addEventListener("loadeddata", this.clearInitialLoading)
    this.diagnostics = createPlaybackDiagnostics(this)
    this.sync = () => {
      const data = this.el.dataset
      const source = data.src || ""
      // A new file starts a new opening; HLS session replacements and stalls do not.
      if (this.fileId !== data.fileId) {
        this.fileId = data.fileId
        skin.setAttribute("data-initial-loading", "")
      }
      const signature = `${data.videoId}:${source}`
      if (this.signature === signature) {
        this.video.dataset.pausedServer = data.pausedServer
        this.control?.updated?.call(this.context)
        return
      }
      this.signature = signature
      this.control?.destroyed.call(this.context)
      this.control = null
      this.video.pause()
      delete this.video.fileTimeline
      this.video.removeAttribute("src")
      this.video.load()
      this.video.id = data.videoId
      for (const key of Object.keys(this.video.dataset)) delete this.video.dataset[key]
      Object.assign(this.video.dataset, data)
      if (!source) return
      this.control = data.sessionId ? TranscodeVideo : VideoError
      this.context = {
        el: this.video, pushEvent: (...args) => this.pushEvent(...args),
        reportPlaybackError: () => this.diagnostics.reportError(),
      }
      this.control.mounted.call(this.context)
      if (!data.sessionId) {
        this.video.src = source
        this.video.play().catch(() => {})
      }
    }
    this.sync()
  },
  updated() { this.sync() },
  disconnected() { this.diagnostics?.disconnected() },
  reconnected() { this.diagnostics?.reconnected() },
  destroyed() {
    this.diagnostics?.destroy()
    this.control?.destroyed.call(this.context)
    this.video.removeEventListener("loadeddata", this.clearInitialLoading)
    this.video.pause()
    this.video.removeAttribute("src")
    this.video.load()
  },
}

export default VideoPlayer
