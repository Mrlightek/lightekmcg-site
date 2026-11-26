import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { createServer } from "node:http"
import { readFile } from "node:fs/promises"
import { resolve, extname } from "node:path"
import { createRequire } from "node:module"
import { fileURLToPath } from "node:url"

const { chromium } = createRequire(import.meta.url)("playwright")
const origin = process.env.STUDIO_MACRO_BROWSER_URL || "http://127.0.0.1:41193"
const engineOrigin = process.env.STUDIO_EDITOR_BROWSER_URL || "http://127.0.0.1:41194"
const root = "/studio/macro_maker"
const dir = (path) => fileURLToPath(new URL(path, import.meta.url))
const releases = {
  photocraft: process.env.PHOTOCRAFT_WEB_ROOT,
  effectcraft: process.env.EFFECTCRAFT_WEB_ROOT
}
const mime = { ".wasm": "application/wasm", ".js": "text/javascript", ".html": "text/html", ".json": "application/json" }

const host = createServer(async (request, response) => {
  try {
    const parts = new URL(request.url, engineOrigin).pathname.split("/").filter(Boolean)
    const engine = parts.shift()
    const path = parts.join("/") || "index.html"
    const base = releases[engine]
    const file = resolve(base, path)
    assert(file.startsWith(resolve(base) + "/"))
    const js = ["studio_editor/features.js", "macro_maker/form_values.js"].includes(path)
    let body = await readFile(js ? dir(`../../app/javascript/${path}`) : file)
    if (path === "index.html") {
      body = body.toString().replace("</body>", `<script type="module">
        import { installStudioFeatures } from "./studio_editor/features.js";
        installStudioFeatures({parentOrigin: ${JSON.stringify(origin)}, engine: ${JSON.stringify(engine)}});
        </script></body>`)
    }
    response.writeHead(200, { "Content-Type": mime[extname(path)] || "application/octet-stream" })
    response.end(body)
  } catch {
    response.writeHead(404).end()
  }
})
await new Promise((done) => host.listen(new URL(engineOrigin).port, "127.0.0.1", done))
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_EXECUTABLE,
  args: ["--enable-unsafe-swiftshader"]
})

try {
  const page = await browser.newPage()
  page.on("pageerror", (error) => console.warn(error.message))
  await page.goto(origin + root)
  const token = await page.locator('meta[name="csrf-token"]').getAttribute("content")
  const headers = { "X-CSRF-Token": token, Accept: "application/json" }
  const proof = await page.request.get(origin + "/studio-fixture.png")
  assert.equal(proof.status(), 200)
  const input = { name: "proof.png", mimeType: "image/png", buffer: await proof.body() }
  const apply = (id, editor, context, file = input, extra = {}) => page.request.post(`${origin}${root}/compositions/${id}/apply`, {
    headers: { ...headers, ...extra }, multipart: { editor, context: JSON.stringify(context), input_file: file, parameters: "{}" }
  })
  const gated = "studio.selection_run_proof"
  const blocked = await apply(gated, "photocraft", { active_selection: false })
  assert.equal(blocked.status(), 422)
  assert.deepEqual((await blocked.json()).missing_context, ["active_selection"])
  const accepted = await apply(gated, "photocraft", { active_selection: true })
  assert.equal(accepted.status(), 200, await accepted.text())
  assert.equal((await accepted.json()).status, "completed")
  assert.equal((await apply(gated, "photocraft", { active_selection: true }, input, { "X-Fixture-User": "foreign" })).status(), 403)
  assert.equal((await apply("studio.foreign_feature", "photocraft", { active_selection: true })).status(), 404)

  const direct = await page.request.post(`${origin}${root}/compositions/studio.run_proof/run?surface=image`, {
    headers, multipart: { input_file: input, parameters: "{}" }
  })
  assert.equal(direct.status(), 200, await direct.text())
  const editorResult = await apply("studio.run_proof", "photocraft", {})
  assert.equal(editorResult.status(), 200, await editorResult.text())
  const download = (url) => page.request.get(origin + url)
  const directFile = await download((await direct.json()).download_url)
  const appliedUrl = (await editorResult.json()).download_url
  assert.deepEqual(await (await download(appliedUrl)).body(), await directFile.body())
  assert.equal((await page.request.get(origin + appliedUrl, { headers: { "X-Fixture-User": "foreign" } })).status(), 404)

  await page.goto(`${origin}${root}/editors/photocraft`)
  const photo = page.frameLocator("iframe")
  const photoFrame = page.frames().find((frame) => frame.url().startsWith(engineOrigin))
  await photoFrame.waitForFunction(() => !document.querySelector("#photocraft_loading"), { timeout: 30000 })
  await photo.getByText("Studio Features", { exact: true }).click()
  const features = photo.getByLabel("Feature", { exact: true })
  await features.locator(`option[value="${gated}"]`).waitFor({ state: "attached" })
  assert.equal(await features.locator('option[value="studio.draft_only"], option[value="studio.foreign_feature"], option[value="studio.motion_run_proof"]').count(), 0)
  await features.selectOption(gated)
  await photo.getByText("This operation requires active selection.").waitFor()
  assert(await photo.getByRole("button", { name: "Run", exact: true }).isDisabled())
  const selected = await page.request.get(origin + "/apply-fixture-photo")
  assert.equal(selected.status(), 200, await selected.text())
  assert.equal(await photo.getByRole("button", { name: /capture/i }).count(), 0)
  await photo.getByLabel("PhotoCraft file").setInputFiles({
    name: "selection.pcraft", mimeType: "application/octet-stream", buffer: await selected.body()
  })
  await photo.getByRole("button", { name: "Run", exact: true }).click()
  const downloadImage = photo.getByRole("button", { name: "Download image", exact: true })
  await downloadImage.waitFor()
  const received = page.waitForEvent("download")
  await downloadImage.click()
  assert.equal((await received).suggestedFilename(), "studio-result.png")

  await features.selectOption("studio.run_proof")
  const opacity = photo.getByLabel("Opacity", { exact: true })
  await opacity.fill("0.62")
  await page.setExtraHTTPHeaders({ "X-Fixture-Engine": "broken" })
  await photo.getByRole("button", { name: "Run", exact: true }).click()
  await photo.getByText(/fixture engine failure/).waitFor()
  assert.equal(await opacity.inputValue(), "0.62")
  await page.setExtraHTTPHeaders({})

  await page.goto(`${origin}${root}/editors/effectcraft`)
  const effectFrame = page.frames().find((frame) => frame.url().startsWith(engineOrigin))
  await effectFrame.waitForFunction(() => window.effectcraftLoad?.readyMs, { timeout: 30000 })
  await effectFrame.evaluate(() => window.effectcraft.execute("comp.new", { name: "Original editor comp", width: 320, height: 320, duration: 1 }))
  await effectFrame.evaluate(async (bytes) => {
    await window.effectcraft.addFile(new File([Uint8Array.from(bytes)], "linked-footage.png"))
    await window.effectcraft.addFile(new File([Uint8Array.from(bytes)], "linked-proxy.png"))
  }, Array.from(input.buffer))
  const exported = await effectFrame.evaluate(async () => {
    await window.effectcraft.execute("file.saveCopy", { path: "/asset-check.ecproj" })
    return JSON.parse(new TextDecoder().decode(window.effectcraft.readFile("/asset-check.ecproj")))
  })
  const footage = Object.values(exported.items).find((item) => item.kind.path?.endsWith("linked-footage.png"))
  const proxy = Object.values(exported.items).find((item) => item.kind.path?.endsWith("linked-proxy.png"))
  assert(footage && proxy)
  await effectFrame.evaluate(async ({ id, proxyPath }) => {
    await window.effectcraft.execute("file.setProxy", { item: id, path: proxyPath })
    await window.effectcraft.execute("layer.addItem", { item: id })
  }, { id: footage.id, proxyPath: proxy.kind.path })

  const missingProject = structuredClone(exported)
  missingProject.items[footage.id].kind.path = "/footage/missing.png"
  missingProject.items[footage.id].kind.sequence = ["/footage/frame-02.png"]
  missingProject.items[footage.id].proxy = { enabled: false, footage: { ...proxy.kind, path: "/proxies/missing-proxy.png" } }
  delete missingProject.items[proxy.id]
  const countRuns = async () => (await (await page.request.get(origin + "/run-fixture-check")).json()).runs.length
  const beforeMissing = await countRuns()
  const missingResponse = await apply("studio.motion_run_proof", "effectcraft", {}, {
    name: "missing.ecproj", mimeType: "application/octet-stream", buffer: Buffer.from(JSON.stringify(missingProject))
  })
  assert.equal(missingResponse.status(), 422, await missingResponse.text())
  const missing = await missingResponse.json()
  assert.equal(missing.errors[0].kind, "missing_assets")
  assert.deepEqual(missing.missing_assets.sort(), ["/footage/frame-02.png", "/footage/missing.png", "/proxies/missing-proxy.png"])
  assert.equal(await countRuns(), beforeMissing, "missing files must not create a run or enqueue a job")

  const effect = page.frameLocator("iframe")
  await effect.getByText("Studio Features", { exact: true }).click()
  const effectChoices = effect.getByLabel("Feature", { exact: true })
  await effectChoices.selectOption("studio.motion_assets_proof")
  assert.equal(await effectChoices.locator('option[value="studio.run_proof"]').count(), 0)
  await effect.getByRole("button", { name: "Run", exact: true }).click()
  await effect.getByText(/Queued…|Rendering…/).waitFor()
  const performed = await page.request.get(origin + "/run-fixture-perform")
  assert.equal(performed.status(), 200, await performed.text())
  const result = await performed.json()
  assert.equal(result.status, "completed", JSON.stringify(result.error_message))
  assert(result.video && result.project && result.reopened && !result.staged_input && !result.staged_assets)
  const finalStatus = await (await page.request.get(origin + `${root}/runs/${result.id}/status`, { headers })).json()
  const video = await download(finalStatus.download_url)
  const frame = spawnSync("ffmpeg", ["-v", "error", "-i", "pipe:0", "-frames:v", "1",
    "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], { input: await video.body() })
  assert.equal(frame.status, 0, frame.stderr?.toString())
  assert(frame.stdout.some((channel) => channel > 20), "the video frame must contain linked media")
  await effect.getByRole("button", { name: "Download video" }).waitFor()
  await effect.getByRole("button", { name: "Open result as a new project" }).click()
  await effectFrame.waitForFunction(() => window.effectcraft.files().some((file) => file.path.startsWith("/studio-result-")))
  const reopenedFile = await effectFrame.evaluate(() => {
    const path = window.effectcraft.files().find((file) => file.path.startsWith("/studio-result-")).path
    return new TextDecoder().decode(window.effectcraft.readFile(path))
  })
  const reopenedItems = Object.values(JSON.parse(reopenedFile).items)
  assert(reopenedItems.some((item) => item.name === "Rendered editor comp"))
  const reopenedFootage = reopenedItems.find((item) => item.kind.path === footage.kind.path)
  assert(reopenedFootage)
  assert.equal(reopenedFootage.proxy.footage.path, proxy.kind.path)
  assert.equal(reopenedFootage.kind.missing, false)
  assert.equal(reopenedFootage.proxy.footage.missing, false)
  await effect.getByRole("button", { name: "Reopen original project snapshot" }).click()

  console.log("PASS editor apply, engine web surfaces, context gating, published menus, scoped relay, PhotoCraft byte parity, and EffectCraft export and reopen")
} finally {
  await browser.close()
  host.close()
}
