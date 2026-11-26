import { Controller } from "@hotwired/stimulus"
import { readMacroField } from "macro_maker/form_values"

export default class extends Controller {
  static targets = ["parameters", "inputs", "message"]

  serialize(event) {
    const entries = { params: [], inputs: [] }
    try {
      for (const field of this.element.querySelectorAll("[data-macro-field]")) {
        const value = readMacroField(field)
        if (value !== undefined) entries[field.dataset.group].push([field.dataset.fieldName, value])
      }
      this.parametersTarget.value = JSON.stringify(Object.fromEntries(entries.params))
      this.inputsTarget.value = JSON.stringify(Object.fromEntries(entries.inputs))
      this.messageTarget.textContent = ""
    } catch (error) {
      event.preventDefault()
      this.messageTarget.textContent = error.message
    }
  }
}
