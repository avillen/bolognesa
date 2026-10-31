const copyTrack = (track) => (track ? { ...track } : null);

export function createMusicQueue() {
  let tracks = [];
  let index = -1;
  let nextEntryId = 0;
  const entry = (track) => ({ ...track, entry_id: ++nextEntryId });

  return {
    snapshot: () => ({ tracks: tracks.map(copyTrack), index }),
    get index() {
      return index;
    },
    current: () => copyTrack(tracks[index]),
    at: (position) => copyTrack(tracks[position]),
    nextIndex: () => (index < tracks.length - 1 ? index + 1 : null),
    previousIndex: () => (index > 0 ? index - 1 : null),
    select(position) {
      if (
        Number.isInteger(position) &&
        position >= 0 &&
        position < tracks.length
      )
        index = position;
    },
    replace(items) {
      tracks = items.slice(0, 500).map(entry);
      index = -1;
    },
    append(track) {
      tracks.push(entry(track));
    },
    clear() {
      tracks = [];
      index = -1;
    },
  };
}
