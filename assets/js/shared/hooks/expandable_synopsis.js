// Only offer disclosure when the browser actually clips the synopsis.
const ExpandableSynopsis = {
  mounted() {
    this.summary = this.el.querySelector("summary")
    this.text = this.el.querySelector(".media-expandable-synopsis-text")
    this.measure = () => {
      const lineHeight = Number.parseFloat(getComputedStyle(this.text).lineHeight)
      const collapsedHeight = this.el.open ? lineHeight * 3 : this.text.clientHeight
      const expandable = this.text.scrollHeight > collapsedHeight + 1
      this.el.dataset.expandable = String(expandable)
      if (expandable) {
        this.summary.removeAttribute("tabindex")
        this.summary.removeAttribute("aria-disabled")
      } else {
        this.el.open = false
        this.summary.setAttribute("tabindex", "-1")
        this.summary.setAttribute("aria-disabled", "true")
      }
    }
    this.preventEmptyToggle = event => {
      if (this.el.dataset.expandable === "false") event.preventDefault()
    }
    this.summary.addEventListener("click", this.preventEmptyToggle)
    this.observer = new ResizeObserver(this.measure)
    this.observer.observe(this.text)
    this.measure()
  },
  updated() {
    this.measure()
  },
  destroyed() {
    this.observer.disconnect()
    this.summary.removeEventListener("click", this.preventEmptyToggle)
  },
}

export default ExpandableSynopsis
