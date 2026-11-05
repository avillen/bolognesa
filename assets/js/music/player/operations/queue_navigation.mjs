import {isReadyTrack} from "../model/selection.mjs"
import {selectionFailed} from "../model/playback_state.mjs"

/** Queue use cases share the session's state; they never construct media URLs. */
export function createQueueNavigation({playback, queue, source, activity, commands, selection, transport, notify}) {
  async function moveTo(index, retry = false, goingBack = false) {
    if (!queue.at(index) || (!retry && index === queue.index)) return
    if (!goingBack && playback.state.selected && queue.current()) {
      playback.backstack.push(queue.current().entry_id)
      if (playback.backstack.length > 100) playback.backstack.shift()
    }
    const command = commands.start()
    const track = queue.at(index)
    queue.select(index)
    if (!isReadyTrack(track)) {
      playback.sourceGeneration++
      source.clear()
      playback.state = selectionFailed({...playback.state, selected: null}, "unavailable")
      playback.lastFailed = {type: "queue", queueIndex: index}
      notify()
      return
    }
    await selection.authorizeTrack(track.id, track.file_id, index, command, {clearOutgoing: true})
  }
  function next() {
    const index = queue.nextIndex()
    if (index !== null) return moveTo(index)
  }
  function previous() {
    if (playback.state.selected && source.snapshot().position > 3) {
      activity.select(playback.state.selected, playback.state.selected.duration_ms / 1000)
      source.restart()
      playback.state.finished = false
      playback.endedGeneration = -1
      notify()
      return
    }
    while (playback.backstack.length) {
      const index = queue.indexOfEntry(playback.backstack.pop())
      if (index >= 0 && index !== queue.index) return moveTo(index, false, true)
    }
  }
  function appendRequest(request, {next = false} = {}) {
    return commands.append(request, tracks => {
      if (playback.destroyed) return false
      if (!tracks.length) throw new Error("empty_queue")
      if (queue.index < 0 && playback.state.selected) {
        queue.replace([playback.state.selected])
        queue.select(0)
      }
      tracks.forEach(track => next ? queue.insertNext(track) : queue.append(track))
      notify()
      return true
    })
  }
  return {
    moveTo, next, previous,
    appendTrack({trackId, fileId}) {
      return appendRequest(transport.selectTrack({trackId, fileId}).then(({track}) => [track]))
    },
    playNext({trackId, fileId}) {
      return appendRequest(transport.selectTrack({trackId, fileId}).then(({track}) => [track]), {next: true})
    },
    appendAlbum({albumId, libraryId}) {
      return appendRequest(transport.loadAlbum({albumId, libraryId}).then(({tracks}) => tracks))
    },
    removeUpcoming(entryId) { if (queue.removeUpcoming(entryId)) notify() },
    clearUpcoming() {
      commands.resetAppends()
      if (queue.clearUpcoming()) notify()
    },
    moveUpcoming(entryId, direction) { if (queue.moveUpcoming(entryId, direction)) notify() },
  }
}
