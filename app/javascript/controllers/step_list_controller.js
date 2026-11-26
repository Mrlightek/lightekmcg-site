import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  start(event) {
    const handle = event.target.closest("[data-drag-handle]")
    if (!handle) return
    this.dragged = this.index(handle)
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", String(this.dragged))
  }

  over(event) {
    if (this.dragged === undefined || !event.target.closest("[data-step-index]")) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  drop(event) {
    const card = event.target.closest("[data-step-index]")
    if (!card || this.dragged === undefined) return
    event.preventDefault()
    const target = this.index(card)
    const bounds = card.getBoundingClientRect()
    const after = event.clientY > bounds.top + bounds.height / 2
    const insertion = target + Number(after)
    this.move(this.dragged, insertion - Number(this.dragged < insertion))
    this.clear()
  }

  clear() {
    this.dragged = undefined
  }

  moveUp(event) {
    const index = this.index(event.currentTarget)
    this.move(index, index - 1)
  }

  moveDown(event) {
    const index = this.index(event.currentTarget)
    this.move(index, index + 1)
  }

  move(from, to) {
    const order = Array.from(this.element.children, (_, index) => index)
    if (to < 0 || to >= order.length || from === to) return
    order.splice(from, 1)
    order.splice(to, 0, from)
    this.element.dispatchEvent(new CustomEvent("macro:step-reordered", { detail: { order }, bubbles: true }))
  }

  index(element) {
    return Number(element.closest("[data-step-index]").dataset.stepIndex)
  }
}
