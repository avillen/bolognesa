import "../../vendor/videojs.min.mjs"
import {createMusicSession} from "./player/session.mjs"
import {connectMediaSession} from "./player/media_session.mjs"
import {connectMusicPlayerView} from "./player/player_view.mjs"

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

export function initializeMusicPlayer(document, {transport, coordinator} = {}) {
  const host = document.querySelector("#music-player-host")
  if (!host) return null
  if (host[instanceKey]) return host[instanceKey]
  const audio = host.querySelector("#music-playback")
  if (!audio || !transport || !coordinator) return null
  installAudioSkin(document, audio)
  const session = createMusicSession({audio, transport})
  const mediaSession = connectMediaSession(document.defaultView, audio, session)
  const unsubscribeActive = coordinator.subscribe(active => mediaSession.setActive(active === audio))
  const unregisterMusic = coordinator.register(audio)
  const view = connectMusicPlayerView(host, session)
  const instance = {audio, session, coordinator, destroy() {
    unregisterMusic(); unsubscribeActive(); view.destroy(); session.destroy(); mediaSession.destroy()
    delete host[instanceKey]
  }}
  Object.defineProperty(host, instanceKey, {value: instance, configurable: true})
  return instance
}
