import {createObservedPlayback} from "../../../shared/observed_playback.mjs"

export function createListeningActivity({clock, report}) {
  const activity = createObservedPlayback({clock, report,
    qualifies: ({elapsed, duration}) => elapsed >= Math.min(30, duration ? duration / 2 : 30)})
  return {
    select(selected, seconds) {
      activity.select(selected ? {id: selected.id, file_id: selected.file_id} : null, seconds)
    },
    update: activity.update,
  }
}
