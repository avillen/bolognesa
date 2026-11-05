import AudioPlayer from "./music/hooks/audio_player.js"
import {createMusicTransport} from "./music/player/adapters/transport.mjs"
import {initializeBrowserRuntime} from "./browser_runtime.mjs"
import {connectTransportDiagnostics} from "./shared/transport_diagnostics.mjs"
// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/bolognesa"
import topbar from "../vendor/topbar.js"
import ImageFallback from "./shared/hooks/image_fallback.js"
import VideoPlayer from "./video/hooks/video_player.js"
import NavigationMenu from "./shared/hooks/navigation_menu.js"
import BrowsePosition from "./shared/hooks/browse_position.js"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
window.bolognesaRuntime = initializeBrowserRuntime(document, {transport: createMusicTransport({csrfToken})})
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {AudioPlayer, ...colocatedHooks, ImageFallback, VideoPlayer, NavigationMenu, BrowsePosition},
})

connectTransportDiagnostics(liveSocket.getSocket())

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#c26e54"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
