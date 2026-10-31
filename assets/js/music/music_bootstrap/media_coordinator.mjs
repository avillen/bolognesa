export function createMediaCoordinator() {
  const participants = new Map()
  let active = null
  return {
    register(mediaElement) {
      if (participants.has(mediaElement)) return participants.get(mediaElement).unregister
      const onPlaying = () => {
        if (active === mediaElement) return
        active = mediaElement
        for (const participant of participants.keys()) {
          if (participant !== mediaElement && !participant.paused) {
            try { participant.pause() } catch { /* Media cleanup must not break the playback that started. */ }
          }
        }
      }
      mediaElement.addEventListener("playing", onPlaying)
      const unregister = () => {
        mediaElement.removeEventListener("playing", onPlaying)
        participants.delete(mediaElement)
        if (active === mediaElement) active = null
      }
      participants.set(mediaElement, {unregister})
      return unregister
    },
  }
}
