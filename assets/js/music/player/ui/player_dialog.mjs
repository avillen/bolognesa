/** Owns modal focus, background inertness, and navigation teardown. */
export function connectPlayerDialog(host, {onCollapse = () => {}} = {}) {
  const player = host.querySelector("#music-player")
  let inertElements = null
  let expanded = false
  let previousFocus = null
  const expandButton = host.querySelector('[data-player-action="expand"]')
  const collapseButton = host.querySelector('[data-player-action="collapse"]')
  const syncExpandedButtons = () => {
    expandButton.hidden = expanded
    collapseButton.hidden = !expanded
    expandButton.setAttribute("aria-expanded", String(expanded))
  }
  const collapse = restoreFocus => {
    if (!expanded) return
    expanded = false
    onCollapse()
    player.dataset.expanded = "false"
    syncExpandedButtons()
    player.setAttribute("role", "region")
    player.removeAttribute("aria-modal")
    inertElements?.forEach(([element, wasInert]) => { element.inert = wasInert })
    inertElements = null
    if (restoreFocus) (previousFocus?.isConnected ? previousFocus : host.querySelector('[data-player-action="expand"]'))?.focus()
    previousFocus = null
  }
  const expand = () => {
    if (expanded) return
    expanded = true
    previousFocus = host.querySelector('[data-player-action="expand"]')
    player.dataset.expanded = "true"
    syncExpandedButtons()
    player.setAttribute("role", "dialog")
    player.setAttribute("aria-modal", "true")
    inertElements = []
    let branch = host
    while (branch.parentElement) {
      const parent = branch.parentElement
      for (const element of parent.children) if (element !== branch) inertElements.push([element, element.inert])
      if (parent === host.ownerDocument.body) break
      branch = parent
    }
    inertElements.forEach(([element]) => { element.inert = true })
    host.querySelector('[data-player-action="collapse"]')?.focus()
  }
  const onKeydown = event => {
    if (event.key === "Escape" && expanded) {
      const menu = player.querySelector("details[open]")
      if (menu) { menu.open = false; menu.querySelector("summary")?.focus(); event.preventDefault(); return }
      event.preventDefault(); collapse(true); return
    }
    if (event.key !== "Tab" || !expanded) return
    const focusable = [...player.querySelectorAll('button:not([disabled]):not([hidden]), input:not([disabled]):not([hidden]), a[href], summary')].filter(element => element.getClientRects().length)
    if (!focusable.length) return
    const first = focusable[0], last = focusable[focusable.length - 1]
    if (event.shiftKey && player.ownerDocument.activeElement === first) { event.preventDefault(); last.focus() }
    else if (!event.shiftKey && player.ownerDocument.activeElement === last) { event.preventDefault(); first.focus() }
  }
  const onPageLoading = () => collapse(false)
  player.ownerDocument.addEventListener("keydown", onKeydown)
  player.ownerDocument.defaultView?.addEventListener("phx:page-loading-start", onPageLoading)
  syncExpandedButtons()
  return {expand, collapse, destroy() {
    collapse(false)
    player.ownerDocument.removeEventListener("keydown", onKeydown)
    player.ownerDocument.defaultView?.removeEventListener("phx:page-loading-start", onPageLoading)
  }}
}
