export function createListeningActivity({clock = () => performance.now() / 1000, report}) {
  let track = null, duration = null, previous = null, elapsed = 0, reported = false
  let generation = 0, retryAt = 0
  return {
    select(selected, seconds) {
      track = selected ? {id: selected.id, file_id: selected.file_id} : null
      duration = Number.isFinite(seconds) && seconds > 0 ? seconds : null
      previous = null; elapsed = 0; reported = false; retryAt = 0; generation++
    },
    update({position, playing, seeking = false, duration: currentDuration}) {
      if (!track || !Number.isFinite(position)) return
      if (Number.isFinite(currentDuration) && currentDuration > 0) duration = currentDuration
      const now = clock()
      if (previous && previous.playing && !seeking && !previous.seeking) {
        const played = position - previous.position
        const wall = now - previous.now
        if (played > 0 && wall > 0 && played <= wall * 2 + 0.5) elapsed += Math.min(played, wall)
      }
      previous = {position, playing, seeking, now}
      if (!reported && now >= retryAt && elapsed >= Math.min(30, duration ? duration / 2 : 30)) {
        reported = true
        const selection = generation
        const failed = () => {
          if (generation === selection) { reported = false; retryAt = clock() + 15 }
        }
        try { Promise.resolve(report(track)).catch(failed) } catch { failed() }
      }
    },
  }
}
