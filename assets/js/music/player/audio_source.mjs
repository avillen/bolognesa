/** Browser media effects. Track authorization, queue and retry policy belong to the session. */
export function createAudioSource(audio) {
  const clear = () => {
    audio.pause()
    audio.removeAttribute("src")
    audio.load()
  }
  return {
    load(src) { audio.src = src; audio.load() },
    clear,
    play: () => audio.play(),
    pause: () => audio.pause(),
    restart() { audio.currentTime = 0 },
    seek(seconds) {
      if (!Number.isFinite(seconds) || !Number.isFinite(audio.duration) || audio.duration <= 0) return
      audio.currentTime = Math.min(audio.duration, Math.max(0, seconds))
    },
    snapshot: () => ({
      paused: Boolean(audio.paused),
      position: Number.isFinite(audio.currentTime) ? audio.currentTime : 0,
      duration: Number.isFinite(audio.duration) && audio.duration > 0 ? audio.duration : null,
    }),
  }
}
