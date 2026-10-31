const mediaEvents = ["loadedmetadata", "durationchange", "timeupdate", "play", "playing", "pause", "ended", "error", "emptied"]

const copyTrack = track => track ? {...track} : null

export function createMusicSession({audio, transport}) {
  let state = {selected: null, queue: [], queueIndex: -1, paused: true, position: 0, duration: null, loading: false, finished: false, error: null}
  let commandGeneration = 0
  let sourceGeneration = 0
  let endedGeneration = -1
  let destroyed = false
  let activeAbort = null
  let lastFailed = null
  const subscribers = new Set()

  const snapshot = () => ({...state, selected: copyTrack(state.selected), queue: state.queue.map(copyTrack), queueCount: state.queue.length, paused: Boolean(audio.paused), position: Number.isFinite(audio.currentTime) ? audio.currentTime : 0, duration: Number.isFinite(audio.duration) && audio.duration > 0 ? audio.duration : null})
  const notify = () => { if (!destroyed) { const value = snapshot(); subscribers.forEach(listener => listener(value)) } }
  const invalidate = () => { commandGeneration++; activeAbort?.abort(); activeAbort = null; return commandGeneration }
  const listen = event => {
    if (destroyed) return
    if (event.type === "ended") {
      if (!state.selected || state.loading) return
      const ended = sourceGeneration
      if (endedGeneration === ended) return
      endedGeneration = ended
      if (state.queueIndex >= 0 && state.queueIndex < state.queue.length - 1) moveTo(state.queueIndex + 1)
      else if (state.queueIndex >= 0) { state.finished = true; state.paused = true; notify() }
      else { state.paused = true; notify() }
      return
    }
    if (event.type === "error" && !state.loading && state.selected) { state.error = {code: "playback_failed", retryable: true}; lastFailed = currentTrackOperation(); notify(); return }
    if (["timeupdate", "loadedmetadata", "durationchange", "play", "playing", "pause", "emptied"].includes(event.type) && !state.selected) return
    notify()
  }
  mediaEvents.forEach(name => audio.addEventListener(name, listen))

  async function authorizeTrack(trackId, fileId, queueIndex, command, {clearOutgoing = false} = {}) {
    const controller = new AbortController()
    activeAbort = controller
    if (clearOutgoing) {
      sourceGeneration++
      audio.pause()
      audio.removeAttribute("src")
      audio.load()
      state.selected = null
      state.position = 0
      state.paused = true
    }
    state.loading = true
    state.error = null
    if (queueIndex !== undefined) state.queueIndex = queueIndex
    notify()
    try {
      const result = await transport.selectTrack({trackId, fileId}, {signal: controller.signal})
      if (command !== commandGeneration || destroyed) return
      const previousSourceGeneration = sourceGeneration
      audio.pause()
      sourceGeneration++
      endedGeneration = -1
      audio.src = result.src
      audio.load()
      state.selected = copyTrack(result.track)
      state.position = 0
      state.duration = null
      state.loading = false
      state.finished = false
      state.error = null
      lastFailed = null
      if (queueIndex === undefined) { state.queue = []; state.queueIndex = -1 }
      notify()
      try {
        await audio.play()
      } catch (error) {
        if (command !== commandGeneration || sourceGeneration <= previousSourceGeneration || error?.name === "AbortError") return
        state.error = {code: error?.name === "NotAllowedError" ? "autoplay_blocked" : "playback_failed", retryable: true}
        lastFailed = currentTrackOperation()
        notify()
      }
    } catch (error) {
      if (command !== commandGeneration || destroyed || error?.name === "AbortError") return
      if (error?.code === "unauthenticated") { clear(); return }
      state.loading = false
      state.error = {code: error?.code || "unavailable", retryable: true}
      lastFailed = {type: "track", trackId, fileId, queueIndex}
      if (queueIndex !== undefined) {
        state.selected = null
        state.paused = true
        sourceGeneration++
        audio.pause()
        audio.removeAttribute("src")
        audio.load()
      }
      notify()
    } finally {
      if (command === commandGeneration) { activeAbort = null; state.loading = false; notify() }
    }
  }

  async function moveTo(index, retry = false) {
    if (index < 0 || index >= state.queue.length || (!retry && index === state.queueIndex)) return
    const command = invalidate()
    const track = state.queue[index]
    state.queueIndex = index
    if (!track || !Number.isSafeInteger(track.id) || track.state !== "ready" || !Number.isSafeInteger(track.file_id)) {
      sourceGeneration++
      audio.pause(); audio.removeAttribute("src"); audio.load()
      state.selected = null; state.position = 0; state.paused = true; state.loading = false
      state.error = {code: "unavailable", retryable: true}; lastFailed = {type: "queue", queueIndex: index}; notify(); return
    }
    await authorizeTrack(track.id, track.file_id, index, command, {clearOutgoing: true})
  }

  return {
    getSnapshot: snapshot,
    subscribe(listener) { if (destroyed) return () => {}; subscribers.add(listener); listener(snapshot()); return () => subscribers.delete(listener) },
    async selectTrack({trackId, fileId}) { const command = invalidate(); lastFailed = null; state.loading = true; state.error = null; notify(); await authorizeTrack(trackId, fileId, undefined, command) },
    async playAlbum({albumId, libraryId}) {
      const command = invalidate(); const controller = new AbortController(); activeAbort = controller
      lastFailed = {type: "album", albumId, libraryId}
      state.loading = true; state.error = null; notify()
      try {
        const result = await transport.loadAlbum({albumId, libraryId}, {signal: controller.signal})
        if (command !== commandGeneration || destroyed) return
        if (!result.tracks?.length) { state.loading = false; state.error = {code: "empty_queue", retryable: true}; notify(); return }
        state.queue = result.tracks.slice(0, 500).map(copyTrack); state.queueIndex = -1
        await moveTo(0)
      } catch (error) {
        if (command !== commandGeneration || destroyed || error?.name === "AbortError") return
        if (error?.code === "unauthenticated") { clear(); return }
        state.loading = false; state.error = {code: error?.code || "unavailable", retryable: true}; lastFailed = {type: "album", albumId, libraryId}; notify()
      } finally { if (command === commandGeneration) { activeAbort = null; state.loading = false; notify() } }
    },
    next() { if (state.queueIndex < state.queue.length - 1) return moveTo(state.queueIndex + 1) },
    previous() { if (state.queueIndex > 0) return moveTo(state.queueIndex - 1) },
    play() {
      if (!state.selected) return
      const generation = sourceGeneration
      state.error = null; notify()
      Promise.resolve(audio.play()).catch(error => {
        if (generation === sourceGeneration && error?.name !== "AbortError") {
          state.error = {code: error?.name === "NotAllowedError" ? "autoplay_blocked" : "playback_failed", retryable: true}; lastFailed = currentTrackOperation(); notify()
        }
      })
    },
    pause() { audio.pause() },
    seek(seconds) { if (Number.isFinite(seconds) && Number.isFinite(audio.duration) && audio.duration > 0) audio.currentTime = Math.min(audio.duration, Math.max(0, seconds)) },
    async retry() {
      if (!lastFailed) return
      const failed = lastFailed
      if (failed.type === "album") return this.playAlbum({albumId: failed.albumId, libraryId: failed.libraryId})
      if (failed.type === "queue") return moveTo(failed.queueIndex, true)
      return authorizeTrack(failed.trackId, failed.fileId, failed.queueIndex, invalidate(), {clearOutgoing: failed.queueIndex !== undefined})
    },
    clear,
    destroy() { clear(); destroyed = true; mediaEvents.forEach(name => audio.removeEventListener(name, listen)); subscribers.clear() },
  }

  function currentTrackOperation() {
    if (state.queueIndex >= 0) {
      const item = state.queue[state.queueIndex]
      return item ? {type: "track", trackId: item.id, fileId: item.file_id, queueIndex: state.queueIndex} : null
    }
    return state.selected ? {type: "track", trackId: state.selected.id, fileId: state.selected.file_id, queueIndex: undefined} : null
  }

  function clear() {
    invalidate(); sourceGeneration++; audio.pause(); audio.removeAttribute("src"); audio.load()
    state = {selected: null, queue: [], queueIndex: -1, paused: true, position: 0, duration: null, loading: false, finished: false, error: null}
    lastFailed = null
    endedGeneration = -1; notify()
  }
}
