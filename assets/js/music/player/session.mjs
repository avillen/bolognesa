import {createMusicQueue} from "./model/queue.mjs"
import {createPlaybackState} from "./model/playback_state.mjs"
import {createSelectionOperations} from "./operations/selection.mjs"
import {createQueueNavigation} from "./operations/queue_navigation.mjs"
import {createPendingOperations} from "./operations/pending_operations.mjs"
import {createListeningActivity} from "./operations/listening_activity.mjs"
import {createCommandTracker} from "./adapters/commands.mjs"
import {createAudioSource} from "./adapters/audio_source.mjs"
import {listenToMedia} from "./adapters/media_events.mjs"

/**
 * Public document-owned playback facade and composition root.
 * Owns one playback record shared with injected operations; screen unmounts only unsubscribe.
 * @param {{audio: HTMLAudioElement, transport: object, clock?: () => number}} dependencies
 */
export function createMusicSession({audio, transport, clock = () => performance.now() / 1000}) {
  const queue = createMusicQueue()
  const source = createAudioSource(audio)
  const commands = createPendingOperations({commands: createCommandTracker()})
  const subscribers = new Set()
  // Lifetime and concurrency state belongs to this session, never to a routed screen.
  const playback = {
    state: createPlaybackState(), destroyed: false, lastFailed: null, backstack: [],
    sourceGeneration: 0, endedGeneration: -1, deferredEndedGeneration: null,
    activityRevision: 0, activityTrackId: null,
  }
  const activity = createListeningActivity({clock, report: track =>
    Promise.resolve(transport.recordActivity?.({trackId: track.id, fileId: track.file_id})).then(() => {
      playback.activityTrackId = track.id
      playback.activityRevision++
      notify()
    })
  })
  const dependencies = {playback, queue, source, activity, commands, transport, notify}
  const selection = createSelectionOperations({...dependencies, clear, onDeferredEnded: handleEnded})
  const navigation = createQueueNavigation({...dependencies, selection})
  const stopListening = listenToMedia(audio, {
    onEvent: event => activity.update({position: audio.currentTime, duration: audio.duration,
      playing: !audio.paused && event.type !== "ended", seeking: audio.seeking || event.type === "seeking"}),
    hasSelection: () => Boolean(playback.state.selected),
    isLoading: () => playback.state.loading,
    onEnded: handleEnded,
    onEndedWhileLoading() {
      if (commands.replacing) playback.deferredEndedGeneration = playback.sourceGeneration
    },
    onError() {
      if (playback.destroyed) return
      playback.state.error = {code: "playback_failed", retryable: true}
      playback.lastFailed = selection.currentTrackOperation()
      notify()
    },
    onChange: notify,
  })

  function snapshot() {
    const queued = queue.snapshot()
    return {...playback.state, selected: playback.state.selected ? {...playback.state.selected} : null,
      activityRevision: playback.activityRevision, activityTrackId: playback.activityTrackId,
      queue: queued.tracks, queueIndex: queued.index, queueCount: queued.tracks.length, ...source.snapshot()}
  }
  function notify() {
    if (playback.destroyed) return
    const value = snapshot()
    subscribers.forEach(listener => listener(value))
  }
  function handleEnded() {
    if (playback.destroyed || playback.endedGeneration === playback.sourceGeneration) return
    playback.endedGeneration = playback.sourceGeneration
    if (queue.index >= 0 && queue.nextIndex() !== null) return navigation.next()
    playback.state.finished = true
    notify()
  }
  function play() {
    if (!playback.state.selected && queue.index < 0 && queue.nextIndex() !== null) return navigation.next()
    if (!playback.state.selected) return
    if (playback.state.finished) {
      if (queue.index >= 0 && queue.nextIndex() !== null) return navigation.next()
      source.restart()
      activity.select(playback.state.selected, playback.state.selected.duration_ms / 1000)
      playback.state.finished = false
      playback.endedGeneration = -1
    }
    playback.state.error = null
    notify()
    void selection.play()
  }
  async function retry() {
    const failed = playback.lastFailed
    if (!failed) return
    if (failed.type === "album") return selection.playAlbum(failed)
    if (failed.type === "queue") return navigation.moveTo(failed.queueIndex, true)
    return selection.authorizeTrack(failed.trackId, failed.fileId, failed.queueIndex,
      commands.start(), {clearOutgoing: failed.queueIndex !== undefined})
  }
  function clear() {
    commands.clear()
    activity.select(null)
    playback.deferredEndedGeneration = null
    playback.sourceGeneration++
    source.clear()
    queue.clear()
    playback.backstack = []
    playback.state = createPlaybackState()
    playback.lastFailed = null
    playback.endedGeneration = -1
    notify()
  }
  return {
    getSnapshot: snapshot,
    subscribe(listener) {
      if (playback.destroyed) return () => {}
      subscribers.add(listener)
      listener(snapshot())
      return () => subscribers.delete(listener)
    },
    selectTrack: selection.selectTrack,
    /** Start at a track/file or zero-based startIndex, using canonical camelCase IDs. */
    playAlbum: selection.playAlbum,
    appendTrack: navigation.appendTrack,
    playNext: navigation.playNext,
    appendAlbum: navigation.appendAlbum,
    removeUpcoming: navigation.removeUpcoming,
    clearUpcoming: navigation.clearUpcoming,
    moveUpcoming: navigation.moveUpcoming,
    next: navigation.next,
    previous: navigation.previous,
    play, pause: source.pause, seek: source.seek, retry, clear,
    destroy() {
      clear()
      playback.destroyed = true
      stopListening()
      subscribers.clear()
    },
  }
}
