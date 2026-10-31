import {createPlayer, videoFeatures, timeFeature, bufferFeature} from "../../vendor/videojs.min.mjs"
import {fileTimeFeature, fileBufferFeature} from "../video_timeline.mjs"
import {createPlaybackDiagnostics} from "../playback_diagnostics.mjs"
import {createPlaybackRecovery} from "../playback_recovery.mjs"
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
    // Slotted feedback remains visible inside the skin's fullscreen container.
    const feedback = document.createElement("div")
    feedback.className = "bolognesa-playback-feedback"
    feedback.setAttribute("role", "alert")
    const message = document.createElement("p")
    const retry = document.createElement("button")
    retry.type = "button"
    retry.addEventListener("click", () => {
      const fileId = this.el.dataset.retryFileId
      if (fileId) this.pushEvent("play", {file_id: fileId})
    })
    feedback.append(message, retry)
    skin.append(feedback)
    this.onFullscreenChange = () => skin.toggleAttribute("data-player-fullscreen",
      (document.fullscreenElement || document.webkitFullscreenElement) === skin)
    document.addEventListener("fullscreenchange", this.onFullscreenChange)
    document.addEventListener("webkitfullscreenchange", this.onFullscreenChange)
    this.video.controls = false
    this.video.autoplay = false
    // Dragging is a preview. Only committing the seek should restart FFmpeg.
    for (const slider of this.el.querySelector("video-skin").shadowRoot.querySelectorAll("media-time-slider")) {
      slider.pauseOnDrag = false
    }
    this.clearInitialLoading = () => skin.removeAttribute("data-initial-loading")
    this.video.addEventListener("loadeddata", this.clearInitialLoading)
    this.recovery = createPlaybackRecovery(this)
    this.scope = this.el.dataset.recoveryScope
    this.diagnostics = createPlaybackDiagnostics(this)
    this.sync = () => {
      const data = this.el.dataset
      const source = data.playbackError ? "" : data.src || ""
      message.textContent = data.playbackError || ""
      retry.textContent = data.retryLabel || ""
      retry.hidden = !data.retryFileId
      feedback.hidden = !data.playbackError
      if (this.scope !== data.recoveryScope) {
        this.diagnostics?.destroy()
        this.scope = data.recoveryScope
        this.diagnostics = createPlaybackDiagnostics(this)
      }
      // A new file starts a new opening; HLS session replacements and stalls do not.
      if (this.fileId !== data.fileId) {
        this.fileId = data.fileId
        skin.setAttribute("data-initial-loading", "")
      }
      const signature = `${data.recoveryScope}:${data.videoId}:${source}:${data.playbackError || ""}`
      if (this.signature === signature) {
        this.video.dataset.pausedServer = data.pausedServer
        this.control?.updated?.call(this.context)
        return
      }
      this.signature = signature
      const retrying = !!this.playbackError && !data.playbackError
      this.playbackError = data.playbackError
      this.recovery.beforeSourceChange()
      if (this.onDirectReady) this.video.removeEventListener("loadedmetadata", this.onDirectReady)
      this.control?.destroyed.call(this.context)
      this.control = null
      this.video.pause()
      delete this.video.fileTimeline
      this.video.removeAttribute("src")
      this.video.load()
      this.video.id = data.videoId
      for (const key of Object.keys(this.video.dataset)) delete this.video.dataset[key]
      Object.assign(this.video.dataset, data)
      if (data.playbackError) return
      if (!this.recovery.source({retry: retrying})) return
      this.control = data.sessionId ? TranscodeVideo : VideoError
      this.context = {
        el: this.video, pushEvent: (...args) => this.pushEvent(...args),
        reportPlaybackError: () => this.diagnostics.reportError(),
        onReady: () => this.recovery.ready(),
      }
      this.control.mounted.call(this.context)
      if (!data.sessionId) {
        this.onDirectReady = () => this.recovery.ready()
        this.video.addEventListener("loadedmetadata", this.onDirectReady, {once: true})
        this.video.src = source
      }
    }
    this.retrySource = () => { this.signature = null; this.sync() }
    this.sync()
  },
  updated() { this.sync() },
  disconnected() { this.diagnostics?.disconnected() },
  reconnected() { this.diagnostics?.reconnected() },
  destroyed() {
    document.removeEventListener("fullscreenchange", this.onFullscreenChange)
    document.removeEventListener("webkitfullscreenchange", this.onFullscreenChange)
    this.recovery?.destroy()
    this.diagnostics?.destroy()
    this.control?.destroyed.call(this.context)
    this.video.removeEventListener("loadeddata", this.clearInitialLoading)
    if (this.onDirectReady) this.video.removeEventListener("loadedmetadata", this.onDirectReady)
    this.video.pause()
    this.video.removeAttribute("src")
    this.video.load()
  },
}

export default VideoPlayer
