import {createWatchedActivity} from "./watched_activity.mjs"

/** Adapts the stable video element and whole-file HLS timeline to Series observations. */
export function createWatchedPlayback({video, report, clock = () => performance.now() / 1000}) {
  const activity = createWatchedActivity({clock, report})
  let config = {}
  const sample = () => {
    if (config.recordWatched !== "true" || config.playbackPhase !== "ready" || config.playbackError ||
        video.dataset.attemptId !== config.attemptId || video.dataset.fileId !== config.fileId ||
        video.fileTimeline?.pending) { activity.suspend(); return }
    activity.update({
      position: (video.fileTimeline?.offset || 0) + video.currentTime,
      duration: video.fileTimeline?.duration || video.duration,
      playing: !video.paused && !video.ended && !video.error,
      seeking: video.seeking,
      ended: video.ended,
    })
  }
  const listeners = {timeupdate: sample, playing: sample, pause: sample, seeking: sample, seeked: sample, ended: sample}
  for (const [name, listener] of Object.entries(listeners)) video.addEventListener(name, listener)
  return {
    update(next) {
      config = next
      activity.select(config.recordWatched === "true" ? config.attemptId : null, config.fileId)
      if (config.playbackPhase !== "ready" || config.playbackError) activity.suspend()
    },
    suspend: () => activity.suspend(),
    destroy() {
      for (const [name, listener] of Object.entries(listeners)) video.removeEventListener(name, listener)
    },
  }
}
