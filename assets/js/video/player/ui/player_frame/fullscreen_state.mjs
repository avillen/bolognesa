/** Mirrors whether the skin is fullscreen as `data-player-fullscreen`, including WebKit's prefixed API. */
export function connectFullscreenState(skin) {
  const document = skin.ownerDocument
  const onChange = () => skin.toggleAttribute("data-player-fullscreen",
    (document.fullscreenElement || document.webkitFullscreenElement) === skin)
  document.addEventListener("fullscreenchange", onChange)
  document.addEventListener("webkitfullscreenchange", onChange)
  return () => {
    document.removeEventListener("fullscreenchange", onChange)
    document.removeEventListener("webkitfullscreenchange", onChange)
  }
}
