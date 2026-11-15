/** Album selection starts at the requested track/file or falls back to the beginning. */
export function albumTracksFrom(tracks, {trackId, fileId, requireTrack = false}) {
  if (trackId == null) return tracks.slice()
  const found = tracks.findIndex(track => track.id === trackId && (fileId == null || track.file_id === fileId))
  if (requireTrack && found < 0) throw Object.assign(new Error(), {code: "unavailable"})
  return tracks.slice(Math.max(0, found))
}

export const isReadyTrack = track => Boolean(track && Number.isSafeInteger(track.id) &&
  track.state === "ready" && Number.isSafeInteger(track.file_id))
