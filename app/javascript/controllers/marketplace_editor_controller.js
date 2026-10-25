import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["panel", "stepButton", "name", "description", "category", "billing", "price", "setup", "trial", "delivery", "welcome", "deliveryNote", "featureField", "previewName", "previewDescription", "previewCategory", "previewPrice", "reviewName", "reviewPrice", "reviewSetup", "reviewTotal", "reviewTrial", "reviewDelivery", "back", "next", "publish"]
  connect() { this.step = 0; this.show(); this.refresh() }
  show() {
    this.panelTargets.forEach((panel, i) => panel.hidden = i !== this.step)
    this.stepButtonTargets.forEach((button, i) => { button.setAttribute("aria-current", i === this.step ? "step" : "false"); button.classList.toggle("is-active", i === this.step) })
    this.backTarget.hidden = this.step === 0
    this.nextTarget.hidden = this.step === 3
    this.publishTarget.hidden = this.step !== 3
  }
  go(event) { this.step = Number(event.currentTarget.dataset.step); this.show(); this.refresh() }
  back() { this.step = Math.max(0, this.step - 1); this.show() }
  next() {
    const invalid = [...this.panelTargets[this.step].querySelectorAll("input,select,textarea")].find(el => !el.checkValidity())
    if (invalid) { invalid.reportValidity(); return }
    this.step = Math.min(3, this.step + 1); this.show(); this.refresh()
  }
  validate(event) {
    const invalid = [...event.target.querySelectorAll("input,select,textarea")].find(el => !el.checkValidity())
    if (!invalid) return
    event.preventDefault()
    this.step = this.panelTargets.findIndex(panel => panel.contains(invalid))
    if (this.step < 0) this.step = 0
    this.show(); invalid.reportValidity()
  }
  refresh() {
    const billing = this.billingTarget.value, recurring = ["monthly", "annual"].includes(billing), free = billing === "free"
    if (!recurring) this.trialTarget.value = "0"
    this.trialTarget.disabled = !recurring
    if (free) { this.priceTarget.value = "0.00"; this.setupTarget.value = "0.00" }
    this.priceTarget.readOnly = free; this.setupTarget.readOnly = free
    const format = v => new Intl.NumberFormat("en-US", {style:"currency", currency:"USD"}).format(Number(v) || 0)
    const rate = free ? "Free" : format(Number(this.priceTarget.value) + (billing === "once" ? Number(this.setupTarget.value) : 0)) + (billing === "monthly" ? " / month" : billing === "annual" ? " / year" : " once")
    this.previewNameTarget.textContent = this.nameTarget.value || "Your service name"
    this.previewDescriptionTarget.textContent = this.descriptionTarget.value || "Your service description"
    this.previewCategoryTarget.textContent = this.categoryTarget.selectedOptions[0].textContent
    this.previewPriceTarget.textContent = rate
    this.reviewNameTarget.textContent = this.nameTarget.value
    this.reviewPriceTarget.textContent = rate
    this.reviewSetupTarget.textContent = format(this.setupTarget.value)
    this.reviewTotalTarget.textContent = format(free ? 0 : Number(this.setupTarget.value) + (recurring && Number(this.trialTarget.value) > 0 ? 0 : Number(this.priceTarget.value)))
    this.reviewTrialTarget.textContent = Number(this.trialTarget.value) ? this.trialTarget.value + " days" : "None"
    this.reviewDeliveryTarget.textContent = this.deliveryTarget.selectedOptions[0].textContent
    this.featureFieldTarget.hidden = this.deliveryTarget.value !== "access"
    const notes = {website:"Creates a customer-owned website from their active subscription. Domain, DNS and TLS activation are still required before it is live.", access:"Grants the selected customer service after the order settles.", manual:"Creates a work request with the customer and order details. Your team completes delivery."}
    this.deliveryNoteTarget.textContent = notes[this.deliveryTarget.value]
  }
}
