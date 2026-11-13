export function queueGroups({queue, queueIndex}) {
  const groups = []
  for (const track of queue.slice(Math.max(0, queueIndex + 1))) {
    const album = track.album || ""
    const artist = track.artist || ""
    const last = groups[groups.length - 1]
    if (album && last && last.album === album && last.artist === artist) last.tracks.push(track)
    else groups.push({album, artist, tracks: [track]})
  }
  return groups
}

export function renderQueue(panel, state) {
  if (!panel) return
  const document = panel.ownerDocument
  const current = panel.querySelector("[data-queue-current]")
  const list = panel.querySelector("[data-queue-list]")
  const empty = panel.querySelector("[data-queue-empty]")
  current.textContent = state.selected?.title || panel.dataset.noCurrent
  const currentArtist = panel.querySelector("[data-queue-artist]")
  if (currentArtist) currentArtist.textContent = state.selected?.artist || ""
  const groups = queueGroups(state)
  const upcoming = groups.flatMap(group => group.tracks)
  const heading = panel.querySelector("[data-queue-heading]")
  if (heading) heading.textContent = heading.dataset.label.replace("__COUNT__", upcoming.length)
  empty.hidden = groups.length > 0
  const clear = panel.querySelector('[data-player-action="clear-upcoming"]')
  if (clear) clear.disabled = groups.length === 0
  let position = 0
  const sections = groups.map(group => {
    const section = document.createElement("li")
    if (group.album) {
      const heading = document.createElement("h4")
      heading.textContent = group.artist ? `${group.album} · ${group.artist}` : group.album
      section.append(heading)
    }
    const tracks = document.createElement("ol")
    for (const track of group.tracks) {
      const item = document.createElement("li")
      const title = document.createElement("span")
      title.textContent = track.title || ""
      const actions = document.createElement("details")
      actions.className = "music-action-menu"
      const summary = document.createElement("summary")
      const moreIcon = document.createElement("span")
      moreIcon.className = "hero-ellipsis-horizontal size-5"
      moreIcon.setAttribute("aria-hidden", "true")
      summary.append(moreIcon)
      summary.setAttribute("aria-label", panel.dataset.optionsLabel || "Options")
      actions.append(summary)
      const menuItems = document.createElement("div")
      menuItems.className = "music-menu-items"
      actions.append(menuItems)
      for (const [action, label, disabled] of [["move-up", panel.dataset.upLabel, position === 0], ["move-down", panel.dataset.downLabel, position === upcoming.length - 1]]) {
        const button = document.createElement("button")
        button.type = "button"
        button.dataset.playerAction = action
        button.dataset.entryId = String(track.entry_id)
        button.textContent = label
        button.title = label
        button.disabled = disabled
        button.setAttribute("aria-label", `${label}: ${track.title || ""}`)
        menuItems.append(button)
      }
      const remove = document.createElement("button")
      remove.type = "button"
      remove.dataset.playerAction = "remove-upcoming"
      remove.dataset.entryId = String(track.entry_id)
      const icon = document.createElement("span")
      icon.className = "hero-x-mark size-4"
      icon.setAttribute("aria-hidden", "true")
      remove.append(icon)
      remove.append(document.createTextNode ? document.createTextNode(panel.dataset.removeLabel) : "")
      remove.title = panel.dataset.removeLabel
      remove.setAttribute("aria-label", `${panel.dataset.removeLabel}: ${track.title || ""}`)
      item.append(title)
      menuItems.append(remove)
      item.append(actions)
      tracks.append(item)
      position++
    }
    section.append(tracks)
    return section
  })
  list.replaceChildren(...sections)
}
