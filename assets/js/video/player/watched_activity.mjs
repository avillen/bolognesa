/** Best-effort client observation, with one delayed retry per issued playback attempt. Clock uses seconds. */
export function createWatchedActivity({clock, report}) {
  let attempt = null, file = null, previous = null, elapsed = 0, reported = false
  let generation = 0, retryAt = 0, retries = 0
  return {
    select(attemptId, fileId) {
      if (attempt === attemptId && file === fileId) return
      attempt = attemptId; file = fileId; previous = null; elapsed = 0; reported = false; retryAt = 0; retries = 0; generation++
    },
    suspend() { previous = null },
    update({position, duration, playing, seeking = false, ended = false}) {
      if (!attempt || !file || !Number.isFinite(position)) return
      const now = clock()
      if (previous?.playing && !previous.seeking && !seeking) {
        const played = position - previous.position
        const wall = now - previous.now
        if (played > 0 && wall > 0 && played <= wall * 2 + 0.5) elapsed += Math.min(played, wall)
      }
      previous = {position, playing, seeking, now}
      if (reported || now < retryAt || elapsed < 120 ||
          !(ended || (Number.isFinite(duration) && duration > 0 && position >= duration * 0.9))) return
      reported = true
      const selection = generation
      const failed = () => {
        if (generation === selection && retries < 1) {
          retries++; reported = false; retryAt = clock() + 15
        }
      }
      try { Promise.resolve(report({attempt_id: attempt, file_id: file})).catch(failed) } catch { failed() }
    },
  }
}
