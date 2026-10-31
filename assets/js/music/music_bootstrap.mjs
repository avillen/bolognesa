import "../../vendor/videojs.min.mjs"
import {createMusicSession} from "./music_bootstrap/session.mjs"
import {createMediaCoordinator} from "./music_bootstrap/media_coordinator.mjs"
import {connectMediaSession} from "./music_bootstrap/media_session.mjs"
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
  const mediaSession = connectMediaSession(document.defaultView, audio, session)
  const coordinator = createMediaCoordinator({onActiveChange: active => mediaSession.setActive(active === audio)})
  const unregisterMusic = coordinator.register(audio)
  const view = connectMusicPlayerView(host, session)
  const instance = {audio, session, coordinator, destroy() {
    unregisterMusic(); view.destroy(); session.destroy(); mediaSession.destroy()
    delete host[instanceKey]
  }}
  Object.defineProperty(host, instanceKey, {value: instance, configurable: true})
  return instance
}
