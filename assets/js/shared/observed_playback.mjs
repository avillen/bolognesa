/** Observed media time and best-effort reporting; clocks use seconds and effects are injected. */
export function createObservedPlayback({clock, report, qualifies}) {
  let selection = null, duration = null, previous = null, elapsed = 0, reported = false
  let generation = 0, retryAt = 0
  return {
    select(selected, seconds) {
      selection = selected
      duration = Number.isFinite(seconds) && seconds > 0 ? seconds : null
      previous = null; elapsed = 0; reported = false; retryAt = 0; generation++
    },
    suspend() { previous = null },
    update({position, playing, seeking = false, duration: currentDuration, ended = false}) {
      if (!selection || !Number.isFinite(position)) return
      if (Number.isFinite(currentDuration) && currentDuration > 0) duration = currentDuration
      const now = clock()
      if (previous && previous.playing && !seeking && !previous.seeking) {
        const played = position - previous.position
        const wall = now - previous.now
        if (played > 0 && wall > 0 && played <= wall * 2 + 0.5) elapsed += Math.min(played, wall)
      }
      previous = {position, playing, seeking, now}
      if (!reported && now >= retryAt && qualifies({elapsed, position, duration, ended})) {
        reported = true
        const current = generation
        const failed = () => {
          if (generation === current) { reported = false; retryAt = clock() + 15 }
        }
        try { Promise.resolve(report(selection)).catch(failed) } catch { failed() }
      }
    },
  }
}
