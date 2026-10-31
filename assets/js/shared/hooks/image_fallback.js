const ImageFallback = {
  mounted() {
    this.hideOnError = () => { this.el.hidden = true }
    this.el.addEventListener("error", this.hideOnError)
    if (this.el.complete && this.el.naturalWidth === 0) this.hideOnError()
  },
  destroyed() {
    this.el.removeEventListener("error", this.hideOnError)
  },
}

export default ImageFallback
