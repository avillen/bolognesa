const storageKey = "bolognesa:browse-positions"

function positions() {
  try {
    const value = JSON.parse(sessionStorage.getItem(storageKey) || "[]")
    return Array.isArray(value) ? value.filter(row => Array.isArray(row) && typeof row[0] === "string" && Number.isFinite(row[1]) && row[1] >= 0).slice(-24) : []
  } catch { return [] }
}

function pageKey() {
  const params = new URLSearchParams(window.location.search)
  for (const key of ["query", "catalog_query"]) {
    if (params.get(key) === "") params.delete(key)
  }
  for (const key of ["page", "catalog_page", "season_page"]) {
    if (params.get(key) === "1") params.delete(key)
  }
  params.sort()
  const search = params.toString()
  return window.location.pathname + (search ? "?" + search : "")
}

export default {
  mounted() {
    this.key = pageKey()
    this.restored = false
    this.save = () => {
      if (!this.restored) return
      try {
        const rows = positions().filter(([key]) => key !== this.key)
        sessionStorage.setItem(storageKey, JSON.stringify([...rows, [this.key, window.scrollY]].slice(-24)))
      } catch { /* Browsing works when storage is unavailable. */ }
    }
    this.restore = () => {
      if (this.restored || this.el.dataset.loading === "true") return
      this.restored = true
      const row = positions().find(([key]) => key === this.key)
      this.frame = requestAnimationFrame(() => window.scrollTo(0, row ? row[1] : 0))
    }
    this.beforeNavigate = () => this.save()
    this.click = event => { if (event.target.closest("a")) this.save() }
    window.addEventListener("pagehide", this.save)
    window.addEventListener("phx:page-loading-start", this.beforeNavigate)
    this.el.addEventListener("click", this.click, true)
    this.restore()
  },
  updated() {
    const key = pageKey()
    if (key !== this.key) {
      this.key = key
      this.restored = false
    }
    this.restore()
  },
  destroyed() {
    cancelAnimationFrame(this.frame)
    window.removeEventListener("pagehide", this.save)
    window.removeEventListener("phx:page-loading-start", this.beforeNavigate)
    this.el.removeEventListener("click", this.click, true)
  },
}
