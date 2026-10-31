import "../../vendor/videojs.min.mjs"
import {createMusicSession} from "./music_bootstrap/session.mjs"
import {createMediaCoordinator} from "./music_bootstrap/media_coordinator.mjs"
import {connectMusicPlayerView} from "./music_bootstrap/player_view.mjs"

const instanceKey = Symbol("bolognesa.musicPlayer")

function installAudioSkin(document, audio) {
  if (audio.closest("audio-player")) return
  const player = document.createElement("audio-player")
  const skin = document.createElement("audio-skin")
  audio.replaceWith(player)
  skin.append(audio)
  player.append(skin)
  audio.controls = false
}

export function initializeMusicPlayer(document, {transport} = {}) {
  const host = document.querySelector("#music-player-host")
  if (!host) return null
  if (host[instanceKey]) return host[instanceKey]
  const audio = host.querySelector("#music-playback")
  if (!audio || !transport) return null
  installAudioSkin(document, audio)
  const session = createMusicSession({audio, transport})
  const coordinator = createMediaCoordinator()
  const unregisterMusic = coordinator.register(audio)
  const view = connectMusicPlayerView(host, session)
  const mediaSession = document.defaultView?.navigator?.mediaSession
  const Metadata = document.defaultView?.MediaMetadata
  let selectedKey = null
  const unsubscribeMetadata = session.subscribe(({selected}) => {
    if (!mediaSession || !Metadata) return
    const key = selected ? JSON.stringify([selected.id, selected.file_id, selected.title, selected.artist, selected.album]) : null
    if (key === selectedKey) return
    selectedKey = key
    mediaSession.metadata = selected ? new Metadata({title: selected.title || "", artist: selected.artist || "", album: selected.album || "", artwork: [{src: "/images/bolognesa-cat.svg", type: "image/svg+xml"}]}) : null
  })
  const instance = {audio, session, coordinator, destroy() { unregisterMusic(); view.destroy(); session.destroy(); unsubscribeMetadata(); delete host[instanceKey] }}
  Object.defineProperty(host, instanceKey, {value: instance, configurable: true})
  return instance
}
