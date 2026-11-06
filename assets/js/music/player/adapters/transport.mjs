const validId = value => Number.isSafeInteger(value) && value > 0
const failure = code => Object.assign(new Error(code), {code})
const validTrack = track => track && (track.id === null || validId(track.id)) && validId(track.file_id) && typeof track.title === "string" && typeof track.state === "string"

function validateSource(src, track) {
  if (typeof src !== "string" || !validId(track.id) || !validId(track.file_id)) throw failure("unavailable")
  if (!new RegExp(`^/music/tracks/${track.id}/media/${track.file_id}$`).test(src)) throw failure("unavailable")
  return src
}

export function createMusicTransport({fetch: fetcher = globalThis.fetch, csrfToken}) {
  async function post(path, body, signal) {
    let response
    try {
      response = await fetcher(path, {method: "POST", credentials: "same-origin", signal, headers: {"Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken}, body: JSON.stringify(body)})
    } catch (error) { if (error?.name === "AbortError") throw error; throw failure("unavailable") }
    if (response.redirected) throw failure("unauthenticated")
    if (response.status === 401) throw failure("unauthenticated")
    if (response.status === 403) throw failure("forbidden")
    if (response.status === 400) throw failure("invalid_request")
    if (response.status === 404) throw failure("not_found")
    if (response.status === 422) throw failure("album_too_large")
    if (!response.ok) throw failure("unavailable")
    if (!response.headers?.get("content-type")?.includes("application/json")) throw failure("unavailable")
    let data
    try { data = await response.json() } catch { throw failure("unavailable") }
    return data
  }
  return {
    async recordActivity({trackId, fileId}) {
      if (!validId(trackId) || !validId(fileId)) throw failure("invalid_request")
      await post("/music/playback/activity", {track_id: trackId, file_id: fileId})
    },
    async selectTrack({trackId, fileId}, {signal} = {}) {
      if (!validId(trackId) || !validId(fileId)) throw failure("invalid_request")
      const data = await post("/music/playback/track", {track_id: trackId, file_id: fileId}, signal)
      if (!validTrack(data?.track) || data.track.id !== trackId || data.track.file_id !== fileId) throw failure("unavailable")
      return {track: data.track, src: validateSource(data.src, data.track)}
    },
    async loadAlbum({albumId, libraryId}, {signal} = {}) {
      if (!validId(albumId) || (libraryId !== null && !validId(libraryId))) throw failure("invalid_request")
      const data = await post("/music/playback/album", {album_id: albumId, library_id: libraryId}, signal)
      if (!Array.isArray(data?.tracks) || data.tracks.length > 500 || !data.tracks.every(validTrack)) throw failure("unavailable")
      return {tracks: data.tracks}
    },
  }
}
