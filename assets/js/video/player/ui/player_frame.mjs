import {createPlaybackFeedback} from "./player_frame/playback_feedback.mjs"
import {connectFullscreenState} from "./player_frame/fullscreen_state.mjs"
import {connectPageHotkeys} from "./player_frame/page_hotkeys.mjs"

export function createPlayerFrame({el, video, pushEvent}) {
  const document = el.ownerDocument
  // Connect the player before its skin so all controls find the player's context.
  const player = document.createElement("bolognesa-video-player")
  const skin = document.createElement("video-skin")
  video.replaceWith(player)
  skin.append(video)
  player.append(skin)
  // Slotted feedback remains visible inside the skin's fullscreen container.
  const feedback = createPlaybackFeedback({el, pushEvent})
  skin.append(feedback.element)
  const disconnectFullscreen = connectFullscreenState(skin)
  const disconnectHotkeys = connectPageHotkeys({skin, video})
  video.controls = false
  video.autoplay = false
  // Dragging is a preview. Only committing the seek should restart FFmpeg.
  for (const slider of skin.shadowRoot.querySelectorAll("media-time-slider")) slider.pauseOnDrag = false
  const clearInitialLoading = () => skin.removeAttribute("data-initial-loading")
  video.addEventListener("loadeddata", clearInitialLoading)
  let fileId
  return {
    update(data) {
      feedback.update(data)
      // Session changes retain the frame; a different file starts a new opening.
      if (fileId === data.fileId) return
      fileId = data.fileId
      skin.setAttribute("data-initial-loading", "")
    },
    destroy() {
      disconnectFullscreen()
      disconnectHotkeys()
      video.removeEventListener("loadeddata", clearInitialLoading)
      feedback.destroy()
    },
  }
}
