import {connectTrackRows} from "./audio_player/track_list.js"

const positiveId = value => {
  if (!/^[1-9]\d*$/.test(value || "")) return null
  const id = Number(value)
  return Number.isSafeInteger(id) ? id : null
}

export default {
  mounted() {
    this.session = window.bolognesaMusicPlayer?.session
    if (!this.session) return
    this.trackRows = connectTrackRows(this.el.querySelector("#music-tracks"), this.session)
    this.onMusicAction = event => {
      const button = event.target.closest?.('[data-music-action]')
      if (!button || !this.el.contains(button)) return
      const action = button.dataset.musicAction
      if (action === "track" || action === "track-only" || action === "album-track" || action === "play-from-here") {
        const trackId = positiveId(button.dataset.trackId)
        const fileId = positiveId(button.dataset.fileId)
        if (!trackId || !fileId) return
        event.preventDefault()
        event.stopImmediatePropagation()
        const current = this.session.getSnapshot().selected
        if (current?.id === trackId && current.file_id === fileId) {
          this.session.getSnapshot().paused ? this.session.play() : this.session.pause()
        } else if (action !== "track-only" && button.dataset.albumId) {
          const albumId = positiveId(button.dataset.albumId)
          const libraryId = button.dataset.libraryId ? positiveId(button.dataset.libraryId) : null
          if (albumId) {
            const playFromHere = this.session.playFromHere || this.session.playAlbumFromTrack || this.session.playAlbumFrom || this.session.playAlbum
            playFromHere.call(this.session, {albumId, libraryId, trackId, fileId})
          } else this.session.selectTrack({trackId, fileId})
        } else this.session.selectTrack({trackId, fileId})
      } else if (action === "append-track" || action === "play-next") {
        const trackId = positiveId(button.dataset.trackId)
        const fileId = positiveId(button.dataset.fileId)
        if (!trackId || !fileId) return
        event.preventDefault()
        event.stopImmediatePropagation()
        const feedback = this.el.querySelector("#music-queue-feedback")
        const operation = action === "play-next" ? this.session.playNext({trackId, fileId}) : this.session.appendTrack({trackId, fileId})
        operation.then(added => {
          if (added && feedback) feedback.textContent = feedback.dataset.added
        }).catch(() => {
          if (feedback) feedback.textContent = feedback.dataset.failed
        })
      } else if (action === "album" || action === "append-album") {
        const albumId = positiveId(button.dataset.albumId)
        const libraryId = button.dataset.libraryId ? positiveId(button.dataset.libraryId) : null
        if (!albumId || (button.dataset.libraryId && !libraryId)) return
        event.preventDefault()
        event.stopImmediatePropagation()
        if (action === "album") this.session.playAlbum({albumId, libraryId})
        else {
          const feedback = this.el.querySelector("#music-queue-feedback")
          this.session.appendAlbum({albumId, libraryId}).then(added => {
            if (added && feedback) feedback.textContent = feedback.dataset.added
          }).catch(() => {
            if (feedback) feedback.textContent = feedback.dataset.failed
          })
        }
      }
    }
    this.el.addEventListener("click", this.onMusicAction, true)
  },
  updated() {
    this.trackRows?.sync()
  },
  destroyed() {
    this.el.removeEventListener("click", this.onMusicAction, true)
    this.trackRows?.destroy()
    this.session = null
  },
}
