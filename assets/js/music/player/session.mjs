import {createPendingOperations} from "./pending_operations.mjs";
import {createAudioSource} from "./audio_source.mjs";
import { createMusicQueue } from "./queue.mjs";
import { createListeningActivity } from "./listening_activity.mjs";
import { listenToMedia } from "./media_events.mjs";

const copyTrack = (track) => (track ? { ...track } : null);

function albumTracksFrom(tracks, {trackId, fileId, startIndex}) {
  if (Number.isInteger(startIndex) && startIndex >= 0 && startIndex < tracks.length) return tracks.slice(startIndex);
  if (trackId == null) return tracks;
  const found = tracks.findIndex(track => track.id === trackId && (fileId == null || track.file_id === fileId));
  return tracks.slice(Math.max(0, found));
}

/**
 * Document-owned playback API. Screen subscribers may detach without stopping audio.
 * @param {{audio: HTMLAudioElement, transport: object, clock?: Function}} dependencies
 * @returns {object} Explicit commands, getSnapshot(), subscribe(listener), and destroy().
 * Snapshots copy selected/queued track data; media position and pause state come from audio.
 */
export function createMusicSession({ audio, transport, clock }) {
  const queue = createMusicQueue();
  let activityRevision = 0;
  let activityTrackId = null;
  const activity = createListeningActivity({clock, report: track =>
    Promise.resolve(transport.recordActivity?.({trackId: track.id, fileId: track.file_id})).then(() => {
      activityTrackId = track.id;
      activityRevision++;
      notify();
    })
  });
  let state = {
    selected: null,
    loading: false,
    finished: false,
    error: null,
  };
  const commands = createPendingOperations();
  const source = createAudioSource(audio);
  let sourceGeneration = 0;
  let endedGeneration = -1;
  let destroyed = false;
  let lastFailed = null;
  let backstack = [];
  let deferredEndedGeneration = null;
  const subscribers = new Set();

  const snapshot = () => {
    const queued = queue.snapshot();
    return {
      ...state,
      activityRevision,
      activityTrackId,
      selected: copyTrack(state.selected),
      queue: queued.tracks,
      queueIndex: queued.index,
      queueCount: queued.tracks.length,
      ...source.snapshot(),
    };
  };
  const notify = () => {
    if (destroyed) return;
    const value = snapshot();
    subscribers.forEach((listener) => listener(value));
  };
  const invalidate = () => commands.start();
  const finishReplacement = (token) => {
    const current = commands.finishReplacement(token);
    if (current && deferredEndedGeneration === sourceGeneration && state.selected && !state.loading) {
      deferredEndedGeneration = null;
      handleEnded();
    }
  };
  function handleEnded() {
    if (destroyed || endedGeneration === sourceGeneration) return;
    endedGeneration = sourceGeneration;
    const next = queue.nextIndex();
    if (queue.index >= 0 && next !== null) return moveTo(next);
    state.finished = true;
    notify();
  }
  const stopListening = listenToMedia(audio, {
    onEvent: event => activity.update({position: audio.currentTime, duration: audio.duration, playing: !audio.paused && event.type !== "ended", seeking: audio.seeking || event.type === "seeking"}),
    hasSelection: () => Boolean(state.selected),
    isLoading: () => state.loading,
    onEnded: handleEnded,
    onEndedWhileLoading() {
      if (commands.replacing) deferredEndedGeneration = sourceGeneration;
    },
    onError() {
      if (destroyed) return;
      state.error = { code: "playback_failed", retryable: true };
      lastFailed = currentTrackOperation();
      notify();
    },
    onChange: notify,
  });

  async function authorizeTrack(
    trackId,
    fileId,
    queueIndex,
    command,
    { clearOutgoing = false, replacementQueue = null, replacementAlbum = null } = {},
  ) {
    const signal = commands.signal();
    if (clearOutgoing) {
      sourceGeneration++;
      source.clear();
      state.selected = null;
    }
    state.loading = true;
    state.error = null;
    if (queueIndex !== undefined && !replacementQueue) queue.select(queueIndex);
    notify();
    try {
      const result = await transport.selectTrack(
        { trackId, fileId },
        { signal },
      );
      if (!commands.isCurrent(command) || destroyed) return;
      acceptSelection(result, {queueIndex, replacementQueue});
      await playSource(command);
    } catch (error) {
      if (ignoreFailure(error, command)) return;
      if (error?.code === "unauthenticated") { clear(); return; }
      if (queueIndex !== undefined && !replacementQueue) {
        state.selected = null;
        sourceGeneration++;
        source.clear();
      }
      failSelection(error, replacementAlbum || {type: "track", trackId, fileId, queueIndex});
    } finally {
      if (commands.isCurrent(command)) {
        commands.finish(command);
        state.loading = false;
        notify();
      }
    }
  }

  async function playSource(command) {
    const generation = sourceGeneration;
    try {
      await source.play();
    } catch (error) {
      if (destroyed || generation !== sourceGeneration || error?.name === "AbortError") return;
      if (command !== undefined && !commands.isCurrent(command)) return;
      state.error = {code: error?.name === "NotAllowedError" ? "autoplay_blocked" : "playback_failed", retryable: true};
      lastFailed = currentTrackOperation();
      notify();
    }
  }

  function acceptSelection(result, {queueIndex, replacementQueue}) {
    if (replacementQueue) {
      queue.replace(replacementQueue);
      queue.select(0);
      backstack = [];
    }
    source.pause();
    sourceGeneration++;
    endedGeneration = -1;
    deferredEndedGeneration = null;
    source.load(result.src);
    state.selected = copyTrack(result.track);
    activity.select(state.selected, state.selected.duration_ms / 1000);
    state.loading = false;
    state.finished = false;
    state.error = null;
    lastFailed = null;
    if (queueIndex === undefined) { queue.clear(); backstack = []; }
    notify();
  }

  const ignoreFailure = (error, command) => destroyed || !commands.isCurrent(command) || error?.name === "AbortError";
  function failSelection(error, operation) {
    if (error?.code === "unauthenticated") { clear(); return; }
    state.loading = false;
    state.error = {code: error?.code || "unavailable", retryable: true};
    lastFailed = operation;
    notify();
  }

  async function moveTo(index, retry = false, goingBack = false) {
    if (!queue.at(index) || (!retry && index === queue.index)) return;
    if (!goingBack && state.selected && queue.current()) {
      backstack.push(queue.current().entry_id);
      if (backstack.length > 100) backstack.shift();
    }
    const command = invalidate();
    const track = queue.at(index);
    queue.select(index);
    if (
      !track ||
      !Number.isSafeInteger(track.id) ||
      track.state !== "ready" ||
      !Number.isSafeInteger(track.file_id)
    ) {
      sourceGeneration++;
      source.clear();
      state.selected = null;
      state.loading = false;
      state.error = { code: "unavailable", retryable: true };
      lastFailed = { type: "queue", queueIndex: index };
      notify();
      return;
    }
    await authorizeTrack(track.id, track.file_id, index, command, {
      clearOutgoing: true,
    });
  }

  function appendRequest(request, {next = false} = {}) {
    return commands.append(request, tracks => {
      if (destroyed) return false;
      if (!tracks.length) throw new Error("empty_queue");
      if (queue.index < 0 && state.selected) {
        queue.replace([state.selected]);
        queue.select(0);
      }
      tracks.forEach(track => next ? queue.insertNext(track) : queue.append(track));
      notify();
      return true;
    });
  }

  async function playAlbumAt({albumId, libraryId = null, trackId: requestedTrackId = null,
    fileId: requestedFileId = null, startIndex: requestedIndex = null} = {}) {
    commands.resetAppends();
    const replacement = commands.beginReplacement();
    const command = invalidate();
    const signal = commands.signal();
    lastFailed = {
      type: "album",
      albumId,
      libraryId,
      trackId: requestedTrackId,
      fileId: requestedFileId,
      startIndex: requestedIndex,
    };
    state.loading = true;
    state.error = null;
    notify();
    try {
      const result = await transport.loadAlbum(
        { albumId, libraryId },
        { signal },
      );
      if (!commands.isCurrent(command) || destroyed) return;
      if (!result.tracks?.length) {
        state.loading = false;
        state.error = { code: "empty_queue", retryable: true };
        notify();
        return;
      }
      const selectedTracks = albumTracksFrom(result.tracks, {trackId: requestedTrackId, fileId: requestedFileId, startIndex: requestedIndex});
      const first = selectedTracks[0];
      if (
        !Number.isSafeInteger(first.id) ||
        first.state !== "ready" ||
        !Number.isSafeInteger(first.file_id)
      ) {
        throw Object.assign(new Error("unavailable"), { code: "unavailable" });
      }
      await authorizeTrack(first.id, first.file_id, 0, command, {
        replacementQueue: selectedTracks,
        replacementAlbum: { type: "album", albumId, libraryId },
      });
    } catch (error) {
      if (ignoreFailure(error, command)) return;
      failSelection(error, {type: "album", albumId, libraryId, trackId: requestedTrackId,
        fileId: requestedFileId, startIndex: requestedIndex});
    } finally {
      finishReplacement(replacement);
      if (commands.isCurrent(command)) {
        commands.finish(command);
        state.loading = false;
        notify();
      }
    }
  }

  const session = {
    getSnapshot: snapshot,
    subscribe(listener) {
      if (destroyed) return () => {};
      subscribers.add(listener);
      listener(snapshot());
      return () => subscribers.delete(listener);
    },
    async selectTrack({ trackId, fileId }) {
      commands.resetAppends();
      const replacement = commands.beginReplacement();
      const command = invalidate();
      lastFailed = null;
      state.loading = true;
      state.error = null;
      notify();
      try {
        await authorizeTrack(trackId, fileId, undefined, command);
      } finally {
        finishReplacement(replacement);
      }
    },
    /** Start an album at a track/file or zero-based startIndex. IDs use camelCase. */
    playAlbum(input) {
      return playAlbumAt(input);
    },
    appendTrack({ trackId, fileId }) {
      return appendRequest(transport.selectTrack({ trackId, fileId }).then(({track}) => [track]));
    },
    playNext({ trackId, fileId }) {
      return appendRequest(transport.selectTrack({ trackId, fileId }).then(({track}) => [track]), { next: true });
    },
    appendAlbum({ albumId, libraryId }) {
      return appendRequest(transport.loadAlbum({ albumId, libraryId }).then(({tracks}) => tracks));
    },
    removeUpcoming(entryId) {
      if (queue.removeUpcoming(entryId)) notify();
    },
    clearUpcoming() {
      commands.resetAppends();
      if (queue.clearUpcoming()) notify();
    },
    moveUpcoming(entryId, direction) {
      if (queue.moveUpcoming(entryId, direction)) notify();
    },
    next() {
      const index = queue.nextIndex();
      if (index !== null) return moveTo(index);
    },
    previous() {
      if (state.selected && audio.currentTime > 3) {
        activity.select(state.selected, state.selected.duration_ms / 1000);
        source.restart();
        state.finished = false;
        endedGeneration = -1;
        notify();
        return;
      }
      while (backstack.length) {
        const index = queue.indexOfEntry(backstack.pop());
        if (index >= 0 && index !== queue.index) return moveTo(index, false, true);
      }
    },
    play() {
      if (!state.selected && queue.index < 0 && queue.nextIndex() !== null)
        return moveTo(queue.nextIndex());
      if (!state.selected) return;
      if (state.finished) {
        const next = queue.nextIndex();
        if (queue.index >= 0 && next !== null) return moveTo(next);
        source.restart();
        activity.select(state.selected, state.selected.duration_ms / 1000);
        state.finished = false;
        endedGeneration = -1;
      }
      state.error = null;
      notify();
      void playSource();
    },
    pause() {
      source.pause();
    },
    seek: seconds => source.seek(seconds),
    async retry() {
      if (!lastFailed) return;
      const failed = lastFailed;
      if (failed.type === "album")
        return this.playAlbum({
          albumId: failed.albumId,
          libraryId: failed.libraryId,
          trackId: failed.trackId,
          fileId: failed.fileId,
          startIndex: failed.startIndex,
        });
      if (failed.type === "queue") return moveTo(failed.queueIndex, true);
      return authorizeTrack(
        failed.trackId,
        failed.fileId,
        failed.queueIndex,
        invalidate(),
        { clearOutgoing: failed.queueIndex !== undefined },
      );
    },
    clear,
    destroy() {
      clear();
      destroyed = true;
      stopListening();
      subscribers.clear();
    },
  };

  return session;

  function currentTrackOperation() {
    const index = queue.index;
    if (index >= 0) {
      const item = queue.current();
      return item
        ? {
            type: "track",
            trackId: item.id,
            fileId: item.file_id,
            queueIndex: index,
          }
        : null;
    }
    return state.selected
      ? {
          type: "track",
          trackId: state.selected.id,
          fileId: state.selected.file_id,
          queueIndex: undefined,
        }
      : null;
  }

  function clear() {
    commands.clear();
    activity.select(null);
    deferredEndedGeneration = null;
    sourceGeneration++;
    source.clear();
    queue.clear();
    backstack = [];
    state = {
      selected: null,
      loading: false,
      finished: false,
      error: null,
    };
    lastFailed = null;
    endedGeneration = -1;
    notify();
  }
}
