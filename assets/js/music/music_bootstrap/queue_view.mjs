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
  const groups = queueGroups(state)
  const upcoming = groups.flatMap(group => group.tracks)
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
      const actions = document.createElement("div")
      for (const [action, label, disabled] of [["move-up", panel.dataset.upLabel, position === 0], ["move-down", panel.dataset.downLabel, position === upcoming.length - 1]]) {
        const button = document.createElement("button")
        button.type = "button"
        button.dataset.playerAction = action
        button.dataset.entryId = String(track.entry_id)
        button.textContent = action === "move-up" ? "↑" : "↓"
        button.title = label
        button.disabled = disabled
        button.setAttribute("aria-label", `${label}: ${track.title || ""}`)
        actions.append(button)
      }
      const remove = document.createElement("button")
      remove.type = "button"
      remove.dataset.playerAction = "remove-upcoming"
      remove.dataset.entryId = String(track.entry_id)
      remove.textContent = panel.dataset.removeLabel
      remove.setAttribute("aria-label", `${panel.dataset.removeLabel}: ${track.title || ""}`)
      item.append(title)
      actions.append(remove)
      item.append(actions)
      tracks.append(item)
      position++
    }
    section.append(tracks)
    return section
  })
  list.replaceChildren(...sections)
}
