/** Best-effort client observation, once per issued playback attempt. Clock uses seconds. */
export function createWatchedActivity({clock, report}) {
  let attempt = null, file = null, previous = null, elapsed = 0, reported = false
  return {
    select(attemptId, fileId) {
      if (attempt === attemptId && file === fileId) return
      attempt = attemptId; file = fileId; previous = null; elapsed = 0; reported = false
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
      if (reported || elapsed < 120 ||
          !(ended || (Number.isFinite(duration) && duration > 0 && position >= duration * 0.9))) return
      reported = true
      // A lost observation is allowed, and must not turn into another report for this attempt.
      try { Promise.resolve(report({attempt_id: attempt, file_id: file})).catch(() => {}) } catch {}
    },
  }
}
