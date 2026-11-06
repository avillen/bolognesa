const positiveId = value => {
  if (!/^[1-9]\d*$/.test(value || "")) return null
  const id = Number(value)
  return Number.isSafeInteger(id) ? id : null
}
const trackActions = new Set(["track", "track-only", "album-track", "play-from-here", "append-track", "play-next", "resume-album"])
const albumActions = new Set(["album", "append-album"])

/** Parse only declared screen actions; DOM strings stop at this boundary. */
export function parseMusicAction({dataset}) {
  const type = dataset.musicAction
  if (!trackActions.has(type) && !albumActions.has(type)) return null
  const albumId = positiveId(dataset.albumId)
  const libraryId = dataset.libraryId ? positiveId(dataset.libraryId) : null
  if (albumActions.has(type)) {
    if (!albumId || (dataset.libraryId && !libraryId)) return null
    return {type, albumId, libraryId}
  }
  const trackId = positiveId(dataset.trackId), fileId = positiveId(dataset.fileId)
  if (!trackId || !fileId) return null
  if (type === "resume-album" && (!albumId || (dataset.libraryId && !libraryId))) return null
  return {type, trackId, fileId, albumId, libraryId}
}

function playTrack(session, {type, trackId, fileId, albumId, libraryId}) {
  const current = session.getSnapshot()
  if (current.selected?.id === trackId && current.selected.file_id === fileId) {
    return current.paused ? session.play() : session.pause()
  }
  if (type !== "track-only" && albumId) return session.playAlbum({albumId, libraryId, trackId, fileId})
  return session.selectTrack({trackId, fileId})
}
const handlers = {
  track: playTrack,
  "track-only": playTrack,
  "album-track": playTrack,
  "play-from-here": playTrack,
  "resume-album": (session, {albumId, libraryId, trackId, fileId}) =>
    session.playAlbum({albumId, libraryId, trackId, fileId, requireTrack: true}),
  "append-track": (session, {trackId, fileId}) => session.appendTrack({trackId, fileId}),
  "play-next": (session, {trackId, fileId}) => session.playNext({trackId, fileId}),
  album: (session, {albumId, libraryId}) => session.playAlbum({albumId, libraryId}),
  "append-album": (session, {albumId, libraryId}) => session.appendAlbum({albumId, libraryId}),
}
export const isQueueAction = ({type}) => ["append-track", "play-next", "append-album"].includes(type)
export const executeMusicAction = (session, command) => handlers[command.type](session, command)
