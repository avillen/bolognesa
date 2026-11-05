import { createCommandTracker } from "./session/commands.js";
import { createMusicQueue } from "./session/queue.js";
import { createListeningActivity } from "./session/listening_activity.mjs";
import { listenToMedia } from "./session/media_events.js";

const copyTrack = (track) => (track ? { ...track } : null);

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
    paused: true,
    position: 0,
    duration: null,
    loading: false,
    finished: false,
    error: null,
  };
  const commands = createCommandTracker();
  let sourceGeneration = 0;
  let endedGeneration = -1;
  let destroyed = false;
  let lastFailed = null;
  let sessionGeneration = 0;
  let appendChain = Promise.resolve();
  let backstack = [];
  let pendingReplacement = null;
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
      paused: Boolean(audio.paused),
      position: Number.isFinite(audio.currentTime) ? audio.currentTime : 0,
      duration:
        Number.isFinite(audio.duration) && audio.duration > 0
          ? audio.duration
          : null,
    };
  };
  const notify = () => {
    if (!destroyed) {
      const value = snapshot();
      subscribers.forEach((listener) => listener(value));
    }
  };
  const invalidate = () => commands.start();
  const beginReplacement = () => {
    let finish;
    const done = new Promise((resolve) => { finish = resolve; });
    const token = { done, finish };
    pendingReplacement = token;
    return token;
  };
  const finishReplacement = (token) => {
    const current = pendingReplacement === token;
    if (current) pendingReplacement = null;
    token.finish();
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
    state.paused = true;
    notify();
  }
  const stopListening = listenToMedia(audio, {
    onEvent: event => activity.update({position: audio.currentTime, duration: audio.duration, playing: !audio.paused && event.type !== "ended", seeking: audio.seeking || event.type === "seeking"}),
    hasSelection: () => Boolean(state.selected),
    isLoading: () => state.loading,
    onEnded: handleEnded,
    onEndedWhileLoading() {
      if (pendingReplacement) deferredEndedGeneration = sourceGeneration;
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
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
      state.selected = null;
      state.position = 0;
      state.paused = true;
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
      const previousSourceGeneration = sourceGeneration;
      if (replacementQueue) {
        queue.replace(replacementQueue);
        queue.select(0);
        backstack = [];
      }
      audio.pause();
      sourceGeneration++;
      endedGeneration = -1;
      deferredEndedGeneration = null;
      audio.src = result.src;
      audio.load();
      state.selected = copyTrack(result.track);
      activity.select(state.selected, state.selected.duration_ms / 1000);
      state.position = 0;
      state.duration = null;
      state.loading = false;
      state.finished = false;
      state.error = null;
      lastFailed = null;
      if (queueIndex === undefined) { queue.clear(); backstack = []; }
      notify();
      try {
        await audio.play();
      } catch (error) {
        if (
          !commands.isCurrent(command) ||
          sourceGeneration <= previousSourceGeneration ||
          error?.name === "AbortError"
        )
          return;
        state.error = {
          code:
            error?.name === "NotAllowedError"
              ? "autoplay_blocked"
              : "playback_failed",
          retryable: true,
        };
        lastFailed = currentTrackOperation();
        notify();
      }
    } catch (error) {
      if (
        !commands.isCurrent(command) ||
        destroyed ||
        error?.name === "AbortError"
      )
        return;
      if (error?.code === "unauthenticated") {
        clear();
        return;
      }
      state.loading = false;
      state.error = { code: error?.code || "unavailable", retryable: true };
      lastFailed = replacementAlbum || { type: "track", trackId, fileId, queueIndex };
      if (queueIndex !== undefined && !replacementQueue) {
        state.selected = null;
        state.paused = true;
        sourceGeneration++;
        audio.pause();
        audio.removeAttribute("src");
        audio.load();
      }
      notify();
    } finally {
      if (commands.isCurrent(command)) {
        commands.finish(command);
        state.loading = false;
        notify();
      }
    }
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
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
      state.selected = null;
      state.position = 0;
      state.paused = true;
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

  function appendRequest(request, { next = false } = {}) {
    const generation = sessionGeneration;
    const replacement = pendingReplacement;
    const pending = request.then(
      (result) => ({ result }),
      (error) => ({ error }),
    );
    const operation = appendChain.then(async () => {
      if (replacement) await replacement.done;
      const { result, error } = await pending;
      if (destroyed || generation !== sessionGeneration) return false;
      if (error) throw error;
      if (!result.length) throw new Error("empty_queue");
      if (queue.index < 0 && state.selected) {
        queue.replace([state.selected]);
        queue.select(0);
      }
      result.forEach((track) => next ? queue.insertNext(track) : queue.append(track));
      notify();
      return true;
    });
    appendChain = operation.catch(() => {});
    return operation;
  }

  async function playAlbumAt({albumId, libraryId = null, trackId: requestedTrackId = null,
    fileId: requestedFileId = null, startIndex: requestedIndex = null} = {}) {
    sessionGeneration++;
    appendChain = Promise.resolve();
    const replacement = beginReplacement();
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
      let start = 0;
      if (Number.isInteger(requestedIndex) && requestedIndex >= 0 && requestedIndex < result.tracks.length) {
        start = requestedIndex;
      } else if (requestedTrackId != null) {
        const found = result.tracks.findIndex(
          (track) =>
            track.id === requestedTrackId &&
            (requestedFileId == null || track.file_id === requestedFileId),
        );
        if (found >= 0) start = found;
      }
      const selectedTracks = result.tracks.slice(start);
      if (!selectedTracks.length) {
        state.loading = false;
        state.error = { code: "empty_queue", retryable: true };
        notify();
        return;
      }
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
      if (
        !commands.isCurrent(command) ||
        destroyed ||
        error?.name === "AbortError"
      )
        return;
      if (error?.code === "unauthenticated") {
        clear();
        return;
      }
      state.loading = false;
      state.error = { code: error?.code || "unavailable", retryable: true };
      lastFailed = {
        type: "album",
        albumId,
        libraryId,
        trackId: requestedTrackId,
        fileId: requestedFileId,
        startIndex: requestedIndex,
      };
      notify();
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
      sessionGeneration++;
      appendChain = Promise.resolve();
      const replacement = beginReplacement();
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
      sessionGeneration++;
      appendChain = Promise.resolve();
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
        audio.currentTime = 0;
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
        audio.currentTime = 0;
        activity.select(state.selected, state.selected.duration_ms / 1000);
        state.finished = false;
        endedGeneration = -1;
      }
      const generation = sourceGeneration;
      state.error = null;
      notify();
      Promise.resolve(audio.play()).catch((error) => {
        if (generation === sourceGeneration && error?.name !== "AbortError") {
          state.error = {
            code:
              error?.name === "NotAllowedError"
                ? "autoplay_blocked"
                : "playback_failed",
            retryable: true,
          };
          lastFailed = currentTrackOperation();
          notify();
        }
      });
    },
    pause() {
      audio.pause();
    },
    seek(seconds) {
      if (
        Number.isFinite(seconds) &&
        Number.isFinite(audio.duration) &&
        audio.duration > 0
      )
        audio.currentTime = Math.min(audio.duration, Math.max(0, seconds));
    },
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
    sessionGeneration++;
    activity.select(null);
    appendChain = Promise.resolve();
    pendingReplacement = null;
    deferredEndedGeneration = null;
    invalidate();
    sourceGeneration++;
    audio.pause();
    audio.removeAttribute("src");
    audio.load();
    queue.clear();
    backstack = [];
    state = {
      selected: null,
      paused: true,
      position: 0,
      duration: null,
      loading: false,
      finished: false,
      error: null,
    };
    lastFailed = null;
    endedGeneration = -1;
    notify();
  }
}
