import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.request = new AbortController()
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request.abort()
  }

  schedule() {
    this.timer = setTimeout(() => this.check(), 2000)
  }

  async check() {
    const { signal } = this.request
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        signal
      })
      if (response.ok && response.status !== 204) {
        const stream = await response.text()
        if (!signal.aborted) window.Turbo.renderStreamMessage(stream)
        return
      }
      if (response.status === 404 || response.status === 403) return
    } catch {
      if (signal.aborted) return
    }
    if (!signal.aborted) this.schedule()
  }
}
