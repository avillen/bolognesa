import { createCommandTracker } from "./session/commands.js";
import { createMusicQueue } from "./session/queue.js";
import { listenToMedia } from "./session/media_events.js";

const copyTrack = (track) => (track ? { ...track } : null);

export function createMusicSession({ audio, transport }) {
  const queue = createMusicQueue();
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
  const subscribers = new Set();

  const snapshot = () => {
    const queued = queue.snapshot();
    return {
      ...state,
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
  const stopListening = listenToMedia(audio, {
    hasSelection: () => Boolean(state.selected),
    isLoading: () => state.loading,
    onEnded() {
      if (destroyed || endedGeneration === sourceGeneration) return;
      endedGeneration = sourceGeneration;
      const next = queue.nextIndex();
      if (queue.index >= 0 && next !== null) return moveTo(next);
      if (queue.index >= 0) state.finished = true;
      state.paused = true;
      notify();
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
    { clearOutgoing = false } = {},
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
    if (queueIndex !== undefined) queue.select(queueIndex);
    notify();
    try {
      const result = await transport.selectTrack(
        { trackId, fileId },
        { signal },
      );
      if (!commands.isCurrent(command) || destroyed) return;
      const previousSourceGeneration = sourceGeneration;
      audio.pause();
      sourceGeneration++;
      endedGeneration = -1;
      audio.src = result.src;
      audio.load();
      state.selected = copyTrack(result.track);
      state.position = 0;
      state.duration = null;
      state.loading = false;
      state.finished = false;
      state.error = null;
      lastFailed = null;
      if (queueIndex === undefined) queue.clear();
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
      lastFailed = { type: "track", trackId, fileId, queueIndex };
      if (queueIndex !== undefined) {
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

  async function moveTo(index, retry = false) {
    if (!queue.at(index) || (!retry && index === queue.index)) return;
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

  function appendRequest(request) {
    const generation = sessionGeneration;
    const pending = request.then(
      (result) => ({ result }),
      (error) => ({ error }),
    );
    const operation = appendChain.then(async () => {
      const { result, error } = await pending;
      if (destroyed || generation !== sessionGeneration) return false;
      if (error) throw error;
      if (!result.length) throw new Error("empty_queue");
      if (queue.index < 0 && state.selected) {
        queue.replace([state.selected]);
        queue.select(0);
      }
      result.forEach((track) => queue.append(track));
      notify();
      return true;
    });
    appendChain = operation.catch(() => {});
    return operation;
  }

  return {
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
      const command = invalidate();
      lastFailed = null;
      state.loading = true;
      state.error = null;
      notify();
      await authorizeTrack(trackId, fileId, undefined, command);
    },
    async playAlbum({ albumId, libraryId }) {
      sessionGeneration++;
      appendChain = Promise.resolve();
      const command = invalidate();
      const signal = commands.signal();
      lastFailed = { type: "album", albumId, libraryId };
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
        queue.replace(result.tracks);
        await moveTo(0);
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
        lastFailed = { type: "album", albumId, libraryId };
        notify();
      } finally {
        if (commands.isCurrent(command)) {
          commands.finish(command);
          state.loading = false;
          notify();
        }
      }
    },
    appendTrack({ trackId, fileId }) {
      return appendRequest(transport.selectTrack({ trackId, fileId }).then(({track}) => [track]));
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
    next() {
      const index = queue.nextIndex();
      if (index !== null) return moveTo(index);
    },
    previous() {
      const index = queue.previousIndex();
      if (index !== null) return moveTo(index);
    },
    play() {
      if (!state.selected && queue.index < 0 && queue.nextIndex() !== null)
        return moveTo(queue.nextIndex());
      if (!state.selected) return;
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
    appendChain = Promise.resolve();
    invalidate();
    sourceGeneration++;
    audio.pause();
    audio.removeAttribute("src");
    audio.load();
    queue.clear();
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
