import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { createServer } from "node:http"
import { readFile } from "node:fs/promises"
import { createRequire } from "node:module"
import { extname, resolve, sep } from "node:path"
import { fileURLToPath } from "node:url"
import { inflateRawSync } from "node:zlib"

const { chromium } = createRequire(import.meta.url)("playwright")
const studio = process.env.STUDIO_MACRO_BROWSER_URL || "http://127.0.0.1:41193"
const editor = process.env.STUDIO_EDITOR_BROWSER_URL || "http://127.0.0.1:41194"
const builtSite = resolve(process.env.PHOTOCRAFT_WEB_ROOT)
const mime = { ".wasm": "application/wasm", ".js": "text/javascript", ".html": "text/html", ".json": "application/json" }

const host = createServer(async (request, response) => {
  try {
    const path = new URL(request.url, editor).pathname.replace(/^\/photocraft\//, "") || "index.html"
    const destination = resolve(builtSite, path)
    assert(destination.startsWith(builtSite + sep))
    const applicationScript = ["studio_editor/features.js", "macro_maker/form_values.js"].includes(path)
    const source = applicationScript ? fileURLToPath(new URL(`../../app/javascript/${path}`, import.meta.url)) : destination
    let body = await readFile(source)
    if (path === "index.html") {
      body = body.toString().replace("</body>", `<script type="module">
        import { installStudioFeatures } from "./studio_editor/features.js";
        installStudioFeatures({parentOrigin: ${JSON.stringify(studio)}, engine: "photocraft"});
        </script></body>`)
    }
    response.writeHead(200, { "Content-Type": mime[extname(path)] || "application/octet-stream" }).end(body)
  } catch {
    response.writeHead(404).end()
  }
})
await new Promise((done) => host.listen(new URL(editor).port, "127.0.0.1", done))

function manifest(bytes) {
  assert.equal(bytes.readUInt32LE(0), 0x04034b50)
  const nameLength = bytes.readUInt16LE(26)
  assert.equal(bytes.subarray(30, 30 + nameLength).toString(), "manifest.json")
  const start = 30 + nameLength + bytes.readUInt16LE(28)
  const encoded = bytes.subarray(start, start + bytes.readUInt32LE(18))
  return JSON.parse(bytes.readUInt16LE(8) === 8 ? inflateRawSync(encoded) : encoded).document
}

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_EXECUTABLE,
  args: ["--enable-unsafe-swiftshader", "--no-sandbox"] })
try {
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } })
  const proof = await page.request.get(studio + "/studio-fixture.png")
  assert.equal(proof.status(), 200)
  const original = await proof.body()
  const downloads = []
  page.on("download", (file) => downloads.push(file))
  await page.goto(studio + "/studio/macro_maker/editors/photocraft")
  const frame = page.frames().find((entry) => entry.url().startsWith(editor))
  await frame.waitForFunction(() => window.photocraftBridge?.version === 1, undefined, { timeout: 90000 })
  assert.deepEqual(await frame.evaluate(() => Object.keys(window.photocraftBridge).sort()), ["exportBytes", "version"])
  await assert.rejects(frame.evaluate(() => window.photocraftBridge.exportBytes()), /No PhotoCraft document is open/)
  await assert.rejects(frame.evaluate(() => window.photocraftBridge.exportBytes("psd")), /Unsupported PhotoCraft export format/)

  await frame.evaluate((bytes) => {
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(new File([Uint8Array.from(bytes)], "proof-character.png"))
    document.querySelector("#photocraft_canvas").dispatchEvent(new DragEvent("drop", { bubbles: true, dataTransfer }))
  }, Array.from(original))
  const snapshot = async () => Buffer.from(await frame.evaluate(async () => Array.from(await window.photocraftBridge.exportBytes("pcraft"))))
  let unselected
  for (let attempt = 0; attempt < 30 && !unselected; attempt++) {
    try { unselected = await snapshot() } catch (error) {
      if (!error.message.includes("No PhotoCraft document is open")) throw error
      await new Promise((done) => setTimeout(done, 100))
    }
  }
  assert(unselected, "PhotoCraft must open the proof document")
  const defaultBytes = await frame.evaluate(async () => Array.from(await window.photocraftBridge.exportBytes()))
  assert.deepEqual(manifest(Buffer.from(defaultBytes)), manifest(unselected))
  const png = await frame.evaluate(async () => Array.from((await window.photocraftBridge.exportBytes("png")).slice(0, 4)))
  assert.deepEqual(png, [137, 80, 78, 71])
  assert.equal(manifest(unselected).selection, null)
  assert.equal(downloads.length, 0, "bridge export must not trigger a browser download")

  const panel = frame.locator("#lightek-studio-features")
  await panel.getByText("Studio Features", { exact: true }).click()
  await panel.getByLabel("Feature", { exact: true }).selectOption("studio.selection_fill_proof")
  const run = panel.getByRole("button", { name: "Run", exact: true })
  await run.click()
  await panel.getByText("This operation requires active selection.", { exact: true }).waitFor()
  assert.equal(await panel.getByLabel("PhotoCraft file").inputValue(), "")
  await panel.getByText("Studio Features", { exact: true }).click()

  const box = await frame.locator("#photocraft_canvas").boundingBox()
  const x = box.x + box.width * 0.39
  const y = box.y + box.height * 0.45
  await page.mouse.click(box.x + 20, box.y + 148)
  await page.mouse.move(x, y)
  await page.mouse.down()
  await page.mouse.move(x + 70, y + 60, { steps: 10 })
  await page.mouse.up()
  let selected
  for (let attempt = 0; attempt < 15; attempt++) {
    selected = await snapshot()
    if (manifest(selected).selection?.tiles?.length) break
    await new Promise((done) => setTimeout(done, 100))
  }
  assert(manifest(selected).selection?.tiles?.length, "the drawn selection must survive in the native bundle")

  const applyPath = "/studio/macro_maker/compositions/studio.selection_fill_proof/apply"
  const applied = page.waitForResponse((response) => new URL(response.url()).pathname === applyPath)
  await panel.getByText("Studio Features", { exact: true }).click()
  await run.click()
  const response = await applied
  assert.equal(response.status(), 200, await response.text())
  const result = await response.json()
  assert.equal(result.status, "completed")
  await panel.getByRole("button", { name: "Download image" }).waitFor()
  const selectedImage = await (await page.request.get(studio + result.download_url)).body()

  // Keep the flagged gate open only for this negative control so the identical macro can process
  // the pre-selection bytes. The actual Studio UI refused to send those bytes above.
  const token = await page.locator('meta[name="csrf-token"]').getAttribute("content")
  const control = await page.request.post(studio + applyPath, {
    headers: { "X-CSRF-Token": token, Accept: "application/json" },
    multipart: { editor: "photocraft", context: '{"active_selection":true}', parameters: "{}",
      input_file: { name: "unselected.pcraft", mimeType: "application/octet-stream", buffer: unselected } }
  })
  assert.equal(control.status(), 200, await control.text())
  const unselectedImage = await (await page.request.get(studio + (await control.json()).download_url)).body()
  function magentaPixels(pngBytes) {
    const pixels = spawnSync("ffmpeg", ["-v", "error", "-i", "pipe:0", "-frames:v", "1",
      "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], { input: pngBytes })
    assert.equal(pixels.status, 0, pixels.stderr?.toString())
    let count = 0
    for (let i = 0; i < pixels.stdout.length; i += 3) {
      if (pixels.stdout[i] > 240 && pixels.stdout[i + 1] < 20 && pixels.stdout[i + 2] > 240) count++
    }
    return count
  }
  const insideMask = magentaPixels(selectedImage)
  assert(insideMask > 0 && insideMask < magentaPixels(unselectedImage), "the mask must constrain which pixels are filled")
  assert.equal(downloads.length, 0)

  await panel.getByText("Studio Features", { exact: true }).click()
  // The pinned stock build disables Save a Copy for this fixture. Its enabled Save As uses
  // the same Rust browser download path and still downloads when the bridge is installed.
  await page.mouse.click(box.x + 57, box.y + 15)
  const saved = page.waitForEvent("download")
  await page.mouse.click(box.x + 120, box.y + 330)
  assert.match((await saved).suggestedFilename(), /proof-character\.psd$/i)

  await frame.evaluate(() => { window.photocraftBridge.version = 999 })
  await panel.getByText("Studio Features", { exact: true }).click()
  await panel.getByText(/Upload a PhotoCraft/).waitFor()
  assert(await run.isDisabled())
  await panel.getByLabel("PhotoCraft file").setInputFiles({
    name: "selected.pcraft", mimeType: "application/octet-stream", buffer: selected
  })
  const manual = page.waitForResponse((response) => new URL(response.url()).pathname === applyPath)
  await run.click()
  assert.equal((await manual).status(), 200)
  console.log("PASS PhotoCraft v1 bridge, native mask, different applied pixels, native Save As download and upload fallback")
} finally {
  await browser.close()
  host.close()
}
