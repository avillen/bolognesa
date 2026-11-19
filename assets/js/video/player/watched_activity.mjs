import {createObservedPlayback} from "../../shared/observed_playback.mjs"

export function createWatchedActivity({clock, report}) {
  let attempt = null, file = null
  const activity = createObservedPlayback({clock, report,
    qualifies: ({elapsed, position, duration, ended}) => elapsed >= 120 &&
      (ended || (duration > 0 && position >= duration * 0.9))})
  return {
    select(attemptId, fileId) {
      if (attempt === attemptId && file === fileId) return
      attempt = attemptId; file = fileId
      activity.select(attempt && file ? {attempt_id: attempt, file_id: file} : null)
    },
    suspend: activity.suspend,
    update: activity.update,
  }
}
