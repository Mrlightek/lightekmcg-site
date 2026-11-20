import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "status"]

  async copy() {
    const source = this.sourceTarget

    try {
      await navigator.clipboard.writeText(source.value)
      this.statusTarget.textContent = "Copied. Paste the name into the confirmation field."
    } catch {
      source.focus()
      source.select()
      this.statusTarget.textContent = "Name selected. Use your browser’s Copy command."
    }
  }
}
