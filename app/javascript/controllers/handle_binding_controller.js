import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["literal", "select", "display"]

  connect() {
    const initial = JSON.parse(this.element.dataset.initial)
    const handles = JSON.parse(this.element.dataset.priorHandles || "[]")
    const accepted = JSON.parse(this.element.dataset.accepted)
    const options = new Map()
    for (const handle of handles) {
      if (accepted.includes("any") || accepted.includes(handle.type)) {
        options.set(handle.name, { label: `${handle.name} · ${handle.type}`, binding: { $ref: handle.name } })
      }
    }
    let selected = ""
    if (initial && !Array.isArray(initial) && typeof initial === "object") {
      const token = ["$ref", "$param", "$input"].find((name) => Object.hasOwn(initial, name))
      if (token) {
        const identifier = [initial[token]].flat().join(".")
        if (token === "$ref" && typeof initial.$ref === "string" && options.has(identifier)) {
          selected = identifier
        } else {
          selected = "@existing"
          options.set(selected, { label: `${token.slice(1)}: ${identifier}`, binding: initial })
        }
      }
    }
    this.options = options
    // A frame can be restored from a Turbo snapshot with its previous options already populated.
    this.selectTarget.replaceChildren(new Option("Enter a value", ""))
    for (const [key, option] of options) this.selectTarget.add(new Option(option.label, key))
    this.selectTarget.value = selected
    this.fillLiteral(selected ? null : initial)
    this.change()
    this.syncColor = (event) => this.updateColor(event)
    this.element.addEventListener("input", this.syncColor)
  }

  disconnect() {
    this.element.removeEventListener("input", this.syncColor)
  }

  change() {
    const option = this.options.get(this.selectTarget.value)
    this.literalTarget.hidden = Boolean(option)
    this.displayTarget.hidden = !option
    this.displayTarget.textContent = option ? `Bound to ${option.label}` : ""
    if (option) this.element.dataset.binding = JSON.stringify(option.binding)
    else delete this.element.dataset.binding
  }

  fillLiteral(value) {
    if (value === null || value === undefined) return
    const controls = this.literalTarget.querySelectorAll("[data-literal-value]")
    if (this.element.dataset.kind === "point") {
      if (Array.isArray(value)) controls.forEach((control, index) => { control.value = value[index] ?? "" })
    } else if (["polygon", "any"].includes(this.element.dataset.kind)) {
      controls[0].value = JSON.stringify(value)
    } else {
      controls[0].value = value
      if (this.element.dataset.kind === "color") this.updateColor({ target: controls[0] })
      if (this.element.dataset.kind === "layer_id") {
        const label = this.literalTarget.querySelector("[data-layer-value-label]")
        if (label) label.textContent = `Layer ${value}`
      }
    }
  }

  updateColor(event) {
    const picker = this.literalTarget.querySelector("[data-color-picker]")
    if (!picker) return
    const text = this.literalTarget.querySelector("[data-literal-value]")
    if (event.target === picker) text.value = picker.value
    if (event.target === text && /^#[0-9a-f]{6}$/i.test(text.value)) picker.value = text.value
  }
}
