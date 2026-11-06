/** Album selection keeps the existing index precedence and beginning fallback. */
export function albumTracksFrom(tracks, {trackId, fileId, startIndex}) {
  if (Number.isInteger(startIndex) && startIndex >= 0 && startIndex < tracks.length) return tracks.slice(startIndex)
  if (trackId == null) return tracks.slice()
  const found = tracks.findIndex(track => track.id === trackId && (fileId == null || track.file_id === fileId))
  return tracks.slice(Math.max(0, found))
}

export const isReadyTrack = track => Boolean(track && Number.isSafeInteger(track.id) &&
  track.state === "ready" && Number.isSafeInteger(track.file_id))
