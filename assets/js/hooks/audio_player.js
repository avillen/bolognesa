import "../../vendor/videojs.min.mjs"
import AudioError from "./audio_error"
import {connectTrackRows} from "./audio_track_list"

function setExpanded(hook, expanded) {
  if (!hook.playback) return
  const changed = hook.modalActive !== expanded
  hook.playerExpanded = expanded
  hook.playback.dataset.expanded = String(expanded)
  hook.playback.querySelector('[data-player-action="expand"]')?.setAttribute("aria-expanded", String(expanded))
  if (expanded) {
    hook.playback.setAttribute("role", "dialog")
    hook.playback.setAttribute("aria-modal", "true")
    if (!hook.modalActive) {
      hook.backgroundInertState = []
      let branch = hook.playback
      while (branch.parentElement) {
        const parent = branch.parentElement
        for (const element of parent.children) {
          if (element !== branch) hook.backgroundInertState.push([element, element.inert])
        }
        if (parent === document.body) break
        branch = parent
      }
    }
    hook.backgroundInertState.forEach(([element]) => { element.inert = true })
    if (changed) hook.playback.querySelector('[data-player-action="collapse"]')?.focus()
    hook.modalActive = true
  } else {
    hook.playback.setAttribute("role", "region")
    hook.playback.removeAttribute("aria-modal")
    if (hook.modalActive) {
      hook.backgroundInertState?.forEach(([element, wasInert]) => { element.inert = wasInert })
      hook.backgroundInertState = null
      hook.playback.querySelector('[data-player-action="expand"]')?.focus()
    }
    hook.modalActive = false
  }
}

// LiveView owns the frame's data; Video.js owns its children and controls.
export default {
  mounted() {
    this.audio = this.el.querySelector("audio")
    this.playback = this.el
    this.onPresentationClick = event => {
      const action = event.target.closest?.("[data-player-action]")?.dataset.playerAction
      if (!action || !this.playback) return
      setExpanded(this, action === "expand")
    }
    this.onPresentationKeydown = event => {
      if (event.key === "Escape" && this.playback?.dataset.expanded === "true") {
        setExpanded(this, false)
      }
    }
    this.onPresentationFocusin = event => {
      if (this.playback?.dataset.expanded === "true" && !this.playback.contains(event.target)) {
        this.playback.querySelector('[data-player-action="collapse"]')?.focus()
      }
    }
    this.playback?.addEventListener("click", this.onPresentationClick)
    document.addEventListener("keydown", this.onPresentationKeydown)
    document.addEventListener("focusin", this.onPresentationFocusin)
    const player = document.createElement("audio-player")
    const skin = document.createElement("audio-skin")
    this.audio.replaceWith(player)
    skin.append(this.audio)
    player.append(skin)
    this.audio.controls = false
    this.context = {el: this.audio, pushEvent: (...args) => this.pushEvent(...args)}
    this.sync = () => {
      const data = this.el.dataset
      Object.assign(this.audio.dataset, {
        generation: data.generation,
        playRequested: data.playRequested,
        stopped: data.stopped,
      })
      this.audio.querySelector("source").setAttribute("src", data.src)
    }
    this.sync()
    AudioError.mounted.call(this.context)
    this.trackRows = connectTrackRows(this.el, this.audio, (...args) => this.pushEvent(...args))
  },
  updated() {
    this.sync()
    setExpanded(this, this.playerExpanded === true)
    AudioError.updated.call(this.context)
    this.trackRows.sync()
  },
  destroyed() {
    this.playback?.removeEventListener("click", this.onPresentationClick)
    document.removeEventListener("keydown", this.onPresentationKeydown)
    document.removeEventListener("focusin", this.onPresentationFocusin)
    this.backgroundInertState?.forEach(([element, wasInert]) => { element.inert = wasInert })
    this.trackRows.destroy()
    AudioError.destroyed.call(this.context)
    this.audio.pause()
    this.audio.querySelector("source").removeAttribute("src")
    this.audio.load()
  },
}
