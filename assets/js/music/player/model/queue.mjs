const copyTrack = (track) => (track ? { ...track } : null);

export function createMusicQueue() {
  let tracks = [];
  let index = -1;
  let nextEntryId = 0;
  let nextEntries = [];
  // Bumped on every change so views can skip re-rendering an unchanged queue.
  let revision = 0;
  const entry = (track) => ({ ...track, entry_id: ++nextEntryId });

  return {
    snapshot: () => ({ tracks: tracks.map(copyTrack), index, revision }),
    get index() {
      return index;
    },
    current: () => copyTrack(tracks[index]),
    at: (position) => copyTrack(tracks[position]),
    indexOfEntry: (entryId) => tracks.findIndex((track) => track.entry_id === entryId),
    nextIndex: () => (index < tracks.length - 1 ? index + 1 : null),
    select(position) {
      if (
        Number.isInteger(position) &&
        position >= 0 &&
        position < tracks.length
      ) {
        index = position;
        nextEntries = [];
        revision++;
      }
    },
    replace(items) {
      tracks = items.slice(0, 500).map(entry);
      index = -1;
      nextEntries = [];
      revision++;
    },
    append(track) {
      tracks.push(entry(track));
      revision++;
    },
    insertNext(track) {
      const positions = nextEntries.map(id => tracks.findIndex(item => item.entry_id === id)).filter(position => position > index);
      const position = positions.length ? Math.max(...positions) + 1 : index + 1;
      const item = entry(track);
      tracks.splice(position, 0, item);
      nextEntries.push(item.entry_id);
      revision++;
    },
    removeUpcoming(entryId) {
      const position = tracks.findIndex((track) => track.entry_id === entryId);
      if (position <= index || position < 0) return false;
      tracks.splice(position, 1);
      nextEntries = nextEntries.filter(id => id !== entryId);
      revision++;
      return true;
    },
    clearUpcoming() {
      if (index + 1 >= tracks.length) return false;
      tracks.splice(index + 1);
      nextEntries = [];
      revision++;
      return true;
    },
    moveUpcoming(entryId, direction) {
      const position = tracks.findIndex((track) => track.entry_id === entryId);
      const target = position + direction;
      if (![1, -1].includes(direction) || position <= index || target <= index || target >= tracks.length || position < 0) return false;
      [tracks[position], tracks[target]] = [tracks[target], tracks[position]];
      revision++;
      return true;
    },
    clear() {
      tracks = [];
      index = -1;
      nextEntries = [];
      revision++;
    },
  };
}
