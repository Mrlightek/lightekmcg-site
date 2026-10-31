import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template"]
  connect() { this.refresh() }
  add() {
    const index = Date.now().toString() + Math.floor(Math.random() * 1000)
    const html = this.templateTarget.innerHTML.replaceAll("NEW_STEP", index)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.refresh()
  }
  remove(event) { event.currentTarget.closest("[data-step]").remove(); this.refresh() }
  change() { this.refresh() }
  refresh() {
    this.listTarget.querySelectorAll("[data-step]").forEach(section => {
      const selected = section.querySelector("[data-action-select]").value
      section.querySelectorAll("[data-action-fields]").forEach(fields => {
        const active = fields.dataset.actionFields === selected
        fields.hidden = !active
        fields.querySelectorAll("input, textarea, select").forEach(input => { input.disabled = !active })
        const kind = fields.querySelector("[data-section-kind-select]")?.value
        fields.querySelectorAll("[data-section-kind]").forEach(content => {
          const chosen = active && content.dataset.sectionKind === kind
          content.hidden = !chosen
          content.querySelectorAll("input, textarea, select").forEach(input => { input.disabled = !chosen })
        })
      })
    })
  }
}
