import { Controller } from "@hotwired/stimulus"
import { readMacroField } from "macro_maker/form_values"

export default class extends Controller {
  static targets = ["catalog", "card", "header", "steps", "picker", "payload", "status", "surfaceBadge"]

  connect() {
    this.operations = JSON.parse(this.catalogTarget.textContent)
    this.restoreSteps(this.stepsTarget)
  }

  stepsTargetConnected(frame) {
    if (this.operations) this.restoreSteps(frame)
  }

  restoreSteps(frame) {
    this.definition = JSON.parse(frame.querySelector("[data-definition]").textContent)
    this.editing = null
    this.renderSteps()
    this.filterOperations()
    if (frame.dataset.editUrl && location.pathname.includes("/macro_maker/compositions/")) {
      history.replaceState(history.state, "", frame.dataset.editUrl)
    }
    this.statusTarget.textContent = ""
  }

  requestAdd() {
    const id = this.pickerTarget.value
    if (id) this.emit("step-added", { id })
  }

  add({ detail: { id } }) {
    if (!this.operation(id) || !this.saveOpenStep()) return
    this.definition.steps.push({ operation: id, params: {}, inputs: {}, returns: {} })
    this.changed()
    this.renderSteps()
    this.pickerTarget.value = ""
  }

  edit(event) {
    event.preventDefault()
    const index = this.stepIndex(event.currentTarget)
    if (this.editing === index || !this.saveOpenStep()) return

    const step = this.definition.steps[index]
    const operation = this.operation(step.operation)
    const template = Array.from(this.element.querySelectorAll("[data-operation-form]")).find((candidate) =>
      candidate.dataset.operationForm === step.operation &&
      candidate.dataset.operationSurface === operation?.surface)
    if (!template) return

    this.editing = index
    const frame = this.openFrame
    frame.replaceChildren(template.content.cloneNode(true))
    frame.hidden = false
    const priorHandles = this.handlesBefore(index)
    frame.querySelectorAll("[data-macro-field]").forEach((field) => {
      const value = step[field.dataset.group]?.[field.dataset.fieldName]
      if (value !== undefined) field.dataset.initial = JSON.stringify(value)
      field.dataset.priorHandles = JSON.stringify(priorHandles)
      if (value && typeof value === "object" && !Array.isArray(value)) {
        field.querySelector("[data-binding-row]").hidden = false
      }
    })
    frame.querySelectorAll("[data-capture-output]").forEach((field) => {
      field.value = Object.keys(step.returns || {}).find((name) =>
        step.returns[name] === field.dataset.captureOutput) || ""
    })
    frame.querySelector("input:not([type=hidden]), textarea, select")?.focus()
  }

  requestEdit() {
    this.emit("step-edited")
  }

  commit() {
    this.saveOpenStep()
  }

  saveOpenStep() {
    if (this.editing === null) return true

    const frame = this.openFrame
    const step = this.definition.steps[this.editing]
    try {
      const update = { ...step, params: { ...step.params }, inputs: { ...step.inputs }, returns: {} }
      for (const field of frame.querySelectorAll("[data-macro-field]")) {
        const { group, fieldName } = field.dataset
        const value = readMacroField(field)
        if (value === undefined) delete update[group][fieldName]
        else Object.defineProperty(update[group], fieldName, { value, enumerable: true, configurable: true, writable: true })
      }
      for (const field of frame.querySelectorAll("[data-capture-output]")) {
        const name = field.value.trim()
        if (!name) continue
        if (!field.checkValidity()) throw new Error("Handle names start with a lowercase letter and use letters, numbers, or underscores.")
        if (Object.hasOwn(update.returns, name)) throw new Error(`Handle ${name} is already captured in this step.`)
        Object.defineProperty(update.returns, name, { value: field.dataset.captureOutput, enumerable: true })
      }
      const updatedIndex = this.editing
      this.definition.steps[updatedIndex] = update
      this.cancelEdit()
      this.updateCard(this.stepsTarget.querySelectorAll("[data-step-index]")[updatedIndex], update, updatedIndex)
      this.changed()
      return true
    } catch (error) {
      frame.querySelector("[data-step-field-error]").textContent = error.message
      return false
    }
  }

  cancelEdit() {
    if (this.editing === null) return
    const frame = this.openFrame
    frame.hidden = true
    frame.replaceChildren()
    this.editing = null
  }

  requestRemove(event) {
    this.emit("step-removed", { index: this.stepIndex(event.currentTarget) })
  }

  remove({ detail: { index } }) {
    if (this.editing === index) this.cancelEdit()
    else if (!this.saveOpenStep()) return
    this.definition.steps.splice(index, 1)
    this.changed()
    this.renderSteps()
  }

  reorder({ detail: { order } }) {
    if (!this.saveOpenStep()) return
    this.definition.steps = order.map((index) => this.definition.steps[index])
    this.changed()
    this.renderSteps()
  }

  changeSurface(event) {
    this.definition.surface = event.currentTarget.value
    this.surfaceBadgeTarget.textContent = this.definition.surface === "motion" ? "Motion" : "Image"
    this.filterOperations()
    this.changed()
  }

  serialize(event) {
    if (!this.saveOpenStep()) {
      event.preventDefault()
      return
    }

    for (const input of this.headerTarget.querySelectorAll("[data-definition-field]")) {
      if (!input.reportValidity()) {
        event.preventDefault()
        return
      }
      this.definition[input.dataset.definitionField] = input.value.trim()
    }
    this.payloadTarget.value = JSON.stringify(this.definition)
  }

  filterOperations() {
    const ids = [...new Set(this.operations.map((operation) => operation.id))]
    const currentId = this.headerTarget.querySelector('[data-definition-field="id"]').value.trim()
    const operations = ids.map((id) => this.operation(id)).filter((operation) => operation && operation.id !== currentId)
    this.pickerTarget.replaceChildren(new Option("Choose an operation", ""))
    operations.forEach((operation) => this.pickerTarget.add(new Option(operation.display_name, operation.id)))
  }

  operation(id) {
    return this.operations.find((operation) => operation.id === id && operation.surface === this.definition.surface) ||
      this.operations.find((operation) => operation.id === id && operation.surface === "both")
  }

  handlesBefore(index) {
    return this.definition.steps.slice(0, index).flatMap((step) => {
      const outputs = this.operation(step.operation)?.returns || {}
      return Object.entries(step.returns || {}).filter(([, output]) => Object.hasOwn(outputs, output))
        .map(([name, output]) => ({ name, type: outputs[output] }))
    })
  }

  renderSteps() {
    const list = this.stepsTarget.querySelector("[data-step-list]")
    const cards = this.definition.steps.map((step, index) => {
      const card = this.cardTarget.content.firstElementChild.cloneNode(true)
      this.updateCard(card, step, index)
      return card
    })
    list.replaceChildren(...cards)
    this.stepsTarget.querySelector("[data-empty-steps]").hidden = cards.length > 0
    const surface = this.headerTarget.querySelector('[data-definition-field="surface"]')
    surface.disabled = cards.length > 0 || this.headerTarget.querySelector('[data-definition-field="id"]').readOnly
  }

  updateCard(card, step, index) {
    card.dataset.stepIndex = index
    card.querySelector("[data-step-number]").textContent = index + 1
    card.querySelector("[data-step-name]").textContent = this.operation(step.operation)?.display_name || step.operation
    const entries = [...Object.entries(step.params || {}), ...Object.entries(step.inputs || {})]
    const summary = entries.map(([key, value]) => `${key}: ${this.describe(value)}`).join(" · ")
    card.querySelector("[data-step-summary]").textContent = summary || "Default settings"
    card.querySelector("[data-step-form]").id = `step_${index}`
    card.querySelector("[data-step-edit]").href = `#step_${index}`
    card.querySelector('[aria-label="Move step up"]').disabled = index === 0
    card.querySelector('[aria-label="Move step down"]').disabled = index === this.definition.steps.length - 1
  }

  describe(value) {
    if (value?.$ref) return `→ ${[value.$ref].flat().join(".")}`
    if (value?.$param || value?.$input) return `$${[value.$param || value.$input].flat().join(".")}`
    if (Array.isArray(value) && value.length > 4) return `${value.length} points`
    return typeof value === "string" ? value : JSON.stringify(value)
  }

  get openFrame() {
    return this.stepsTarget.querySelector(`#step_${this.editing}`)
  }

  stepIndex(element) {
    return Number(element.closest("[data-step-index]").dataset.stepIndex)
  }

  emit(name, detail = {}) {
    this.element.dispatchEvent(new CustomEvent(`macro:${name}`, { detail, bubbles: true }))
  }

  changed() {
    this.statusTarget.textContent = "Unsaved changes"
  }
}
