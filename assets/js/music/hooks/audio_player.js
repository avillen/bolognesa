import {getBrowserRuntime} from "../../browser_runtime.mjs"
import {connectTrackRows} from "./audio_player/track_list.mjs"

import {parseMusicAction, executeMusicAction, isQueueAction} from "./audio_player/actions.mjs"

export default {
  mounted() {
    this.showQueueFeedback = (feedback, message) => {
      if (!feedback) return
      feedback.textContent = message
      feedback.dataset.visible = "true"
      clearTimeout(this.feedbackTimer)
      this.feedbackTimer = setTimeout(() => {
        feedback.textContent = ""
        delete feedback.dataset.visible
      }, 3000)
    }
    this.session = getBrowserRuntime()?.musicSession
    if (!this.session) return
    this.trackRows = connectTrackRows(this.el.querySelector("#music-tracks"), this.session)
    let revision
    this.stopActivityUpdates = this.session.subscribe(snapshot => {
      if (revision !== undefined && snapshot.activityRevision !== revision && Number.isSafeInteger(snapshot.activityTrackId) && snapshot.activityTrackId > 0) this.pushEvent("listening-activity", {track_id: snapshot.activityTrackId})
      revision = snapshot.activityRevision
    })
    this.onMusicAction = event => {
      const button = event.target.closest?.('[data-music-action]')
      if (!button || !this.el.contains(button)) return
      const command = parseMusicAction(button)
      if (!command) return
      const menu = button.closest?.("details")
      for (const openMenu of this.el.querySelectorAll?.("details[open]") || []) {
        if (openMenu !== menu) openMenu.open = false
      }
      if (menu) { menu.open = false; menu.querySelector("summary")?.focus() }
      event.preventDefault()
      event.stopImmediatePropagation()
      const operation = executeMusicAction(this.session, command)
      if (!isQueueAction(command)) return
      const feedback = this.el.querySelector("#music-queue-feedback")
      operation.then(added => {
        if (added && feedback) this.showQueueFeedback(feedback, feedback.dataset.added)
      }).catch(() => {
        if (feedback) this.showQueueFeedback(feedback, feedback.dataset.failed)
      })
    }

    this.onMenuDismiss = event => {
      const open = this.el.querySelectorAll("details[open]")
      for (const menu of open) {
        if (event.type === "keydown" && event.key === "Escape") { menu.open = false; menu.querySelector("summary")?.focus(); event.stopPropagation(); event.preventDefault() }
        else if (event.type === "click" && !menu.contains(event.target)) menu.open = false
      }
    }
    this.el.ownerDocument?.addEventListener("click", this.onMenuDismiss)
    this.el.ownerDocument?.addEventListener("keydown", this.onMenuDismiss)
    this.el.addEventListener("click", this.onMusicAction, true)
  },
  updated() {
    this.trackRows?.sync()
  },
  destroyed() {
    clearTimeout(this.feedbackTimer)
    this.el.ownerDocument?.removeEventListener("click", this.onMenuDismiss)
    this.el.ownerDocument?.removeEventListener("keydown", this.onMenuDismiss)
    this.el.removeEventListener("click", this.onMusicAction, true)
    this.trackRows?.destroy()
    this.stopActivityUpdates?.()
    this.session = null
  },
}
