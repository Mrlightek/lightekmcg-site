export function readMacroField(field) {
  // The binding controller publishes the selected value without changing the literal controls.
  if (field.dataset.binding) return JSON.parse(field.dataset.binding)
  const controls = Array.from(field.querySelectorAll("[data-literal-value]"))
  const values = controls.map((input) => input.value.trim())
  const label = field.dataset.fieldName
  if (values.every((value) => !value)) return undefined
  if (controls.some((input) => !input.checkValidity())) throw new Error(`Check the value for ${label}.`)

  switch (field.dataset.kind) {
    case "point":
      if (values.some((value) => !value)) throw new Error(`Enter X and Y for ${label}.`)
      return values.map(Number)
    case "number":
    case "integer":
    case "layer_id":
      return Number(values[0])
    case "polygon":
    case "any":
      try {
        return JSON.parse(values[0])
      } catch {
        throw new Error(`Enter valid JSON for ${label}.`)
      }
    default:
      return values[0]
  }
}
