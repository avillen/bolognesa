export function createMediaCoordinator({onActiveChange = () => {}} = {}) {
  const participants = new Map()
  let active = null
  const subscribers = new Set([onActiveChange])
  const notify = () => subscribers.forEach(listener => listener(active))
  return {
    subscribe(listener) { subscribers.add(listener); listener(active); return () => subscribers.delete(listener) },
    destroy() {
      for (const {unregister} of [...participants.values()]) unregister()
      subscribers.clear()
    },
    register(mediaElement) {
      if (participants.has(mediaElement)) return participants.get(mediaElement).unregister
      const onPlaying = () => {
        if (active === mediaElement) return
        active = mediaElement
        notify()
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
        if (active === mediaElement) { active = null; notify() }
      }
      participants.set(mediaElement, {unregister})
      return unregister
    },
  }
}
