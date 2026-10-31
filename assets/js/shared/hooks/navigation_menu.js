export default {
  mounted() {
    this.desktop = window.matchMedia("(min-width: 1024px)")
    this.sync = () => {
      this.el.close()
      if (this.desktop.matches) this.el.setAttribute("open", "")
    }
    this.open = () => {
      if (!this.desktop.matches && !this.el.open) this.el.showModal()
    }
    this.close = () => { if (!this.desktop.matches) this.el.close() }
    this.click = event => {
      if (event.target.closest("a")) this.close()
      if (event.target === this.el) {
        const rect = this.el.getBoundingClientRect()
        if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.close()
      }
    }
    this.el.addEventListener("bolognesa:open-navigation", this.open)
    this.el.addEventListener("bolognesa:close-navigation", this.close)
    this.el.addEventListener("click", this.click)
    this.desktop.addEventListener("change", this.sync)
    this.sync()
  },
  destroyed() {
    this.el.removeEventListener("bolognesa:open-navigation", this.open)
    this.el.removeEventListener("bolognesa:close-navigation", this.close)
    this.el.removeEventListener("click", this.click)
    this.desktop.removeEventListener("change", this.sync)
    this.el.close()
  },
}
