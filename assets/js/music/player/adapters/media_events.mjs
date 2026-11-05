const events = [
  "loadedmetadata",
  "durationchange",
  "timeupdate",
  "seeking",
  "seeked",
  "play",
  "playing",
  "pause",
  "ended",
  "error",
  "emptied",
];
const stateEvents = new Set([
  "timeupdate",
  "loadedmetadata",
  "durationchange",
  "play",
  "playing",
  "pause",
  "emptied",
]);

export function listenToMedia(
  audio,
  { hasSelection, isLoading, onEnded, onEndedWhileLoading, onError, onChange, onEvent },
) {
  const listener = (event) => {
    onEvent?.(event);
    if (event.type === "ended") {
      if (hasSelection()) {
        if (isLoading()) onEndedWhileLoading?.();
        else onEnded();
      }
    } else if (event.type === "error" && !isLoading() && hasSelection()) {
      onError();
    } else if (!stateEvents.has(event.type) || hasSelection()) {
      onChange();
    }
  };
  events.forEach((name) => audio.addEventListener(name, listener));
  return () =>
    events.forEach((name) => audio.removeEventListener(name, listener));
}
