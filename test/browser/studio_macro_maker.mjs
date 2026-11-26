import assert from "node:assert/strict"
import { createRequire } from "node:module"
const { chromium } = createRequire(import.meta.url)("playwright")

const origin = process.env.STUDIO_MACRO_BROWSER_URL || "http://127.0.0.1:41193"
const browser = await chromium.launch(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {})
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } })
  const browserErrors = []
  page.on("response", (response) => {
    if (response.status() >= 400 && response.status() !== 422) browserErrors.push(`${response.status()} ${response.url()}`)
  })
  page.on("pageerror", (error) => browserErrors.push(error.message))
  const path = "/studio/macro_maker"
  await page.goto(origin + path)
  await page.getByRole("link", { name: "Motion", exact: true }).click()
  await page.waitForURL("**/macro_maker?surface=motion")
  await page.getByRole("link", { name: "Image", exact: true }).click()
  await page.getByRole("link", { name: "New Composition" }).click()

  const header = page.locator("#composition_header")
  const list = page.locator("#composition_steps")
  const validation = page.locator("#validation_panel")
  const picker = page.getByLabel("Operation", { exact: true })
  await header.waitFor()
  await list.waitFor()
  await validation.waitFor()
  await page.getByRole("button", { name: "Save Draft" }).waitFor()
  await page.getByRole("button", { name: "Publish", exact: true }).waitFor()
  await picker.locator('option[value="studio.set_layer_opacity"]').waitFor({ state: "attached" })
  assert.deepEqual(await picker.locator("option").evaluateAll((options) =>
    options.filter((option) => option.value).map((option) => option.value)),
  ["studio.add_facial_hair", "studio.run_proof", "studio.set_layer_opacity"])
  await header.getByLabel("Operation ID").fill("studio.browser_proof")
  await header.getByLabel("Name").fill("Browser Proof")
  await header.getByLabel("Description").fill("Hair and opacity proof")

  const network = []
  page.on("request", (request) => network.push(request.url()))
  async function add(operation) {
    await picker.selectOption(operation)
    await page.getByRole("button", { name: "Add Step" }).click()
  }
  await add("studio.add_facial_hair")
  const cards = list.locator("[data-step-index]")
  await cards.first().getByRole("heading", { name: "Add Facial Hair" }).waitFor()
  await cards.first().getByRole("link", { name: "Edit" }).click()
  const first = page.locator("#step_0")
  await first.waitFor({ state: "visible" })
  const density = first.getByLabel("Density", { exact: true })
  assert.equal(await density.inputValue(), "0.85")
  await density.fill("0.52")
  await first.locator('[data-capture-output="hair_layer"]').fill("beard_layer")
  await first.getByRole("button", { name: "Save step" }).click()
  await first.waitFor({ state: "hidden" })
  await cards.first().getByText(/density: 0.52/).waitFor()

  await add("studio.set_layer_opacity")
  await cards.nth(1).getByRole("link", { name: "Edit" }).click()
  const second = page.locator("#step_1")
  await second.getByLabel("Bind layer to output").selectOption("beard_layer")
  await second.getByText("Bound to beard_layer · layer_id").waitFor()
  await second.getByLabel("Opacity", { exact: true }).fill("0.35")
  await second.getByRole("button", { name: "Save step" }).click()
  await second.waitFor({ state: "hidden" })
  await cards.nth(1).getByText(/layer: → beard_layer/).waitFor()
  assert.deepEqual(network, [], "Step editing triggered a network request")

  async function save(label, status) {
    const reply = page.waitForResponse((candidate) =>
      candidate.request().method() === "POST" && candidate.url() === origin + path + "/compositions")
    await page.getByRole("button", { name: label, exact: true }).click()
    const response = await reply
    assert.equal(response.status(), status, await response.text())
    assert.match(response.headers()["content-type"], /turbo-stream/)
    return response.text()
  }
  const firstSave = await save("Save Draft", 200)
  for (const id of ["composition_steps", "composition_header", "validation_panel"]) {
    assert.match(firstSave, new RegExp(`action="replace" target="${id}"`))
  }
  await validation.getByText(/Saved draft version 1/).waitFor()
  await header.getByText(/Tenant · v1/).waitFor()
  await page.waitForURL(/browser_proof\/edit/)

  // Moving the consumer first creates a forward reference. Its card must survive the error stream.
  await cards.nth(1).getByRole("button", { name: "Drag step" }).dragTo(cards.first(), {
    targetPosition: { x: 45, y: 8 }
  })
  await cards.first().getByRole("heading", { name: "Set Layer Opacity" }).waitFor()
  const failed = await save("Save Draft", 422)
  assert.match(failed, /action="replace" target="validation_panel"/)
  assert.doesNotMatch(failed, /target="composition_steps"/)
  await validation.locator('[data-error-kind="unresolved_ref"]').waitFor()
  await cards.first().getByText(/layer: → beard_layer/).waitFor()
  assert.equal(await cards.count(), 2)

  // Replace the failed order with two independent thick steps, then drag to verify compiled order.
  await cards.first().getByRole("button", { name: "Remove" }).click()
  await add("studio.add_facial_hair")
  await cards.nth(1).getByRole("link", { name: "Edit" }).click()
  await page.locator("#step_1").getByLabel("Density", { exact: true }).fill("0.72")
  await page.locator("#step_1").getByRole("button", { name: "Save step" }).click()
  await cards.nth(1).getByRole("button", { name: "Drag step" }).dragTo(cards.first(), {
    targetPosition: { x: 45, y: 8 }
  })
  await cards.first().getByText(/density: 0.72/).waitFor()
  await save("Publish", 200)
  await validation.getByText(/Published version 2/).waitFor()
  const record = await (await page.request.get(origin + "/browser-check")).json()
  const opacity = record.recipe.steps.filter((step) => step.command === "layer.setProps").map((step) => step.params.opacity)
  assert.deepEqual(opacity, [0.72, 0.52])
  await page.reload()
  await page.locator("#composition_header").getByText("Tenant · v2").waitFor()
  await page.locator("#composition_steps").getByText(/density: 0.72/).first().waitFor()
  await page.getByRole("link", { name: "Compositions" }).click()
  await page.getByRole("link", { name: "Browser Proof", exact: true }).first().waitFor()
  assert.equal(await page.getByRole("link", { name: "Browser Proof", exact: true }).count(), 2)
  assert.deepEqual(browserErrors, [])
  console.log("PASS Studio macro maker browser flow, local editing, bindings, Turbo Streams and compiled drag order")
} finally {
  await browser.close()
}
