import {selectionStarted, selectionAccepted, selectionFailed} from "../model/playback_state.mjs"
import {albumTracksFrom, isReadyTrack} from "../model/selection.mjs"

/**
 * Coordinates authorization and source replacement using the session's single playback record.
 * Browser effects, queue, cancellation and lifecycle callbacks are injected by the session.
 * Only an authorized, current response may replace the outgoing source.
 */
export function createSelectionOperations({playback, queue, source, activity, commands, transport,
  notify, clear, onDeferredEnded}) {
  const isCurrent = command => !playback.destroyed && commands.isCurrent(command)
  const ignoreFailure = (error, command) => !isCurrent(command) || error?.name === "AbortError"

  function startSelection() {
    playback.state = selectionStarted(playback.state)
    notify()
  }
  function finishCommand(command) {
    if (!commands.isCurrent(command)) return
    commands.finish(command)
    playback.state.loading = false
    notify()
  }
  function failSelection(error, operation) {
    if (error?.code === "unauthenticated") { clear(); return }
    playback.state = selectionFailed(playback.state, error?.code || "unavailable")
    playback.lastFailed = operation
    notify()
  }
  function finishReplacement(token) {
    const current = commands.finishReplacement(token)
    if (!current || playback.deferredEndedGeneration !== playback.sourceGeneration ||
        !playback.state.selected || playback.state.loading) return
    playback.deferredEndedGeneration = null
    onDeferredEnded()
  }
  async function replace(operation, run) {
    commands.resetAppends()
    const replacement = commands.beginReplacement()
    const command = commands.start()
    playback.lastFailed = operation
    startSelection()
    try {
      await run(command)
    } catch (error) {
      if (!ignoreFailure(error, command)) failSelection(error, operation)
    } finally {
      finishReplacement(replacement)
      // Album preparation may fail before authorizeTrack gets a chance to finish.
      if (operation?.type === "album") finishCommand(command)
    }
  }

  async function authorizeTrack(trackId, fileId, queueIndex, command,
    {clearOutgoing = false, replacementQueue = null, replacementAlbum = null} = {}) {
    const signal = commands.signal()
    if (clearOutgoing) {
      playback.sourceGeneration++
      source.clear()
      playback.state.selected = null
    }
    if (queueIndex !== undefined && !replacementQueue) queue.select(queueIndex)
    startSelection()
    try {
      const result = await transport.selectTrack({trackId, fileId}, {signal})
      if (!isCurrent(command)) return
      acceptSelection(result, {queueIndex, replacementQueue})
      await play(command)
    } catch (error) {
      if (ignoreFailure(error, command)) return
      if (error?.code === "unauthenticated") { clear(); return }
      if (queueIndex !== undefined && !replacementQueue) {
        playback.state.selected = null
        playback.sourceGeneration++
        source.clear()
      }
      failSelection(error, replacementAlbum || {type: "track", trackId, fileId, queueIndex})
    } finally {
      finishCommand(command)
    }
  }
  function acceptSelection(result, {queueIndex, replacementQueue}) {
    if (replacementQueue) {
      queue.replace(replacementQueue)
      queue.select(0)
      playback.backstack = []
    }
    source.pause()
    playback.sourceGeneration++
    playback.endedGeneration = -1
    playback.deferredEndedGeneration = null
    source.load(result.src)
    playback.state = selectionAccepted(playback.state, result.track)
    activity.select(playback.state.selected, playback.state.selected.duration_ms / 1000)
    playback.lastFailed = null
    if (queueIndex === undefined) { queue.clear(); playback.backstack = [] }
    notify()
  }
  async function play(command) {
    const generation = playback.sourceGeneration
    try {
      await source.play()
    } catch (error) {
      if (playback.destroyed || generation !== playback.sourceGeneration || error?.name === "AbortError") return
      if (command !== undefined && !commands.isCurrent(command)) return
      playback.state.error = {code: error?.name === "NotAllowedError" ? "autoplay_blocked" : "playback_failed", retryable: true}
      playback.lastFailed = currentTrackOperation()
      notify()
    }
  }
  function currentTrackOperation() {
    const index = queue.index
    const track = index >= 0 ? queue.current() : playback.state.selected
    return track ? {type: "track", trackId: track.id, fileId: track.file_id,
      queueIndex: index >= 0 ? index : undefined} : null
  }
  function selectTrack({trackId, fileId}) {
    return replace(null, command => authorizeTrack(trackId, fileId, undefined, command))
  }
  function playAlbum({albumId, libraryId = null, trackId = null, fileId = null, startIndex = null} = {}) {
    const operation = {type: "album", albumId, libraryId, trackId, fileId, startIndex}
    return replace(operation, async command => {
      const result = await transport.loadAlbum({albumId, libraryId}, {signal: commands.signal()})
      if (!isCurrent(command)) return
      if (!result.tracks?.length) throw Object.assign(new Error(), {code: "empty_queue"})
      const tracks = albumTracksFrom(result.tracks, {trackId, fileId, startIndex})
      const first = tracks[0]
      if (!isReadyTrack(first)) throw Object.assign(new Error(), {code: "unavailable"})
      await authorizeTrack(first.id, first.file_id, 0, command, {
        replacementQueue: tracks,
        // Preserve the characterized retry behavior tracked separately in #30.
        replacementAlbum: {type: "album", albumId, libraryId},
      })
    })
  }
  return {selectTrack, playAlbum, authorizeTrack, play, currentTrackOperation}
}
