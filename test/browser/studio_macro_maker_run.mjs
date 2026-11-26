import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { createHash } from "node:crypto"
import { createRequire } from "node:module"

const { chromium } = createRequire(import.meta.url)("playwright")
const origin = process.env.STUDIO_MACRO_BROWSER_URL || "http://127.0.0.1:41193"
const root = "/studio/macro_maker"
const path = (id, surface = "image") => `${root}/compositions/${id}/run?surface=${surface}`
const browser = await chromium.launch(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE } : {})

try {
  const page = await browser.newPage()
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  await page.goto(origin + path("studio.add_facial_hair"))
  assert.match(await page.locator("#macro-run-requirements").textContent(), /active selection/)
  assert(await page.getByRole("button", { name: "Run", exact: true }).isDisabled())
  assert.equal(await page.getByLabel("Input image").count(), 1)
  await page.goto(origin + path("studio.animate_layer_position", "motion"))
  assert.equal(await page.getByLabel("Input image").count(), 0)
  assert(await page.getByRole("button", { name: "Run", exact: true }).isDisabled())
  assert.match(await page.locator("#macro-run-requirements").textContent(), /open composition/)

  const published = path("studio.run_proof")
  await page.goto(origin + published)
  await page.getByRole("heading", { name: "Run Run Proof" }).waitFor()
  assert.equal(await page.getByText("Image · v1").count(), 1)
  assert.equal((await page.request.get(origin + path("studio.draft_only"))).status(), 404)

  const token = await page.locator('meta[name="csrf-token"]').getAttribute("content")
  const proof = await page.request.get(origin + "/studio-fixture.png")
  assert.equal(proof.status(), 200)
  const upload = { name: "studio-fixture.png", mimeType: "image/png", buffer: await proof.body() }
  const headers = { "X-CSRF-Token": token, Accept: "application/json" }
  let response = await page.request.post(origin + published, {
    headers, multipart: { input_file: upload, parameters: '{"opacity":1.35}' }
  })
  assert.equal(response.status(), 422)
  const invalid = await response.json()
  assert.equal(invalid.valid, false)
  assert.equal(invalid.errors[0].kind, "invalid_binding")
  assert.match(invalid.errors[0].detail, /opacity/)
  assert.equal((await (await page.request.get(origin + "/run-fixture-check")).json()).runs.length, 0)
  response = await page.request.post(origin + path("studio.add_facial_hair"), {
    headers, multipart: { input_file: upload, parameters: "{}", active_selection: "true" }
  })
  assert.equal(response.status(), 422)

  async function run() {
    const saved = page.waitForResponse((item) => item.url() === origin + published && item.request().method() === "POST")
    await page.getByRole("button", { name: "Run", exact: true }).click()
    return saved
  }
  await page.getByLabel("Input image").setInputFiles(upload)
  await page.getByLabel("Opacity", { exact: true }).fill("0.35")
  response = await run()
  assert.equal(response.status(), 200, await response.text())
  const link = page.locator("#validation_panel").getByRole("link", { name: "Download output" })
  await link.waitFor()
  const download = origin + await link.getAttribute("href")
  const file = await page.request.get(download)
  assert.equal(file.status(), 200)
  assert.match(file.headers()["content-disposition"], /attachment/)
  const bytes = await file.body()
  assert(bytes.length > 0)
  const direct = await (await page.request.get(origin + "/run-fixture-direct")).text()
  assert.equal(createHash("sha256").update(bytes).digest("hex"), direct)
  assert.equal((await page.request.get(download, { headers: { "X-Fixture-Site": "foreign" } })).status(), 404)
  assert.equal((await page.request.get(origin + published, { headers: { "X-Fixture-Site": "foreign" } })).status(), 404)

  await page.setExtraHTTPHeaders({ "X-Fixture-Engine": "broken" })
  await page.getByLabel("Input image").setInputFiles(upload)
  await page.getByLabel("Opacity", { exact: true }).fill("0.62")
  response = await run()
  assert.equal(response.status(), 422, await response.text())
  const failure = page.locator("#validation_panel")
  await failure.getByText("layer.setProps", { exact: true }).waitFor()
  assert.equal(await failure.getByText("Step index", { exact: true }).count(), 1)
  await failure.getByText("fixture engine failure", { exact: true }).waitFor()
  assert.equal(await page.getByLabel("Opacity", { exact: true }).inputValue(), "0.62")
  assert.match(await page.getByLabel("Input image").inputValue(), /studio-fixture\.png$/)
  await page.locator("#macro_recent_runs").getByText("Failed", { exact: false }).waitFor()
  const persisted = await (await page.request.get(origin + "/run-fixture-check")).json()
  assert.equal(persisted.temporary_inputs, 0)
  assert.deepEqual(persisted.runs.map((run) => run.status), ["completed", "failed"])
  assert(persisted.runs[0].operation_record_id)
  assert.equal(persisted.runs[0].version, 1)
  assert.equal(persisted.runs[1].error_message.step_index, 0)
  assert.equal(persisted.runs[1].error_message.reason, "protocol_error")
  await page.setExtraHTTPHeaders({})
  const motion = path("studio.motion_run_proof", "motion")
  await page.goto(origin + motion)
  assert.equal(await page.getByLabel("Input image").count(), 0)
  assert(await page.getByRole("button", { name: "Run", exact: true }).isEnabled())
  async function enqueueMotion() {
    const accepted = page.waitForResponse((item) => item.url() === origin + motion && item.request().method() === "POST")
    await page.getByRole("button", { name: "Run", exact: true }).click()
    const response = await accepted
    assert.equal(response.status(), 202, await response.text())
    const subscription = page.locator("#validation_panel turbo-cable-stream-source")
    await subscription.waitFor({ state: "attached" })
    assert(await subscription.getAttribute("signed-stream-name"))
    assert(await page.getByRole("button", { name: "Running…" }).isDisabled())
  }

  async function performMotion(mode) {
    const performed = await page.request.get(origin + "/run-fixture-perform", {
      headers: mode ? { "X-Fixture-Render": mode } : {}
    })
    assert.equal(performed.status(), 200, await performed.text())
    const result = await performed.json()
    assert.match(result.broadcasts.at(-1) || "", new RegExp(`target="macro_run_${result.id}"`))
    if (result.project) {
      assert(result.reopened, "EffectCraft can reopen the saved project")
      assert.match(result.broadcasts.at(-1), /Download project/)
    }
    return result
  }

  await enqueueMotion()
  const success = await performMotion()
  assert.equal(success.status, "completed", JSON.stringify(success.error_message))
  assert(success.video && success.project)
  assert.match(success.broadcasts.join("\n"), /Rendering/)
  assert.match(success.broadcasts.at(-1), /Download video/)
  const statusPanel = page.locator("#validation_panel")
  const videoLink = statusPanel.getByRole("link", { name: "Download video" })
  await videoLink.waitFor()
  const projectLink = statusPanel.getByRole("link", { name: "Download project" })
  const videoUrl = origin + await videoLink.getAttribute("href")
  const projectUrl = origin + await projectLink.getAttribute("href")
  const video = await page.request.get(videoUrl)
  assert.equal(video.status(), 200)
  assert.match(video.headers()["content-disposition"], /\.mp4/)
  assert.match(video.headers()["content-type"], /video\/mp4/)
  const probe = spawnSync("ffprobe", ["-v", "error", "-select_streams", "v:0",
    "-show_entries", "stream=codec_name", "-of", "csv=p=0", "pipe:0"], { input: await video.body() })
  assert.equal(probe.status, 0, probe.stderr?.toString())
  assert.equal(probe.stdout.toString().trim(), "h264")
  const project = await page.request.get(projectUrl)
  assert.match(project.headers()["content-disposition"], /\.ecproj/)
  assert((await project.json()).savedBy)
  for (const url of [videoUrl, projectUrl, origin + `${root}/runs/${success.id}/status`]) {
    for (const key of ["X-Fixture-Site", "X-Fixture-User"]) {
      assert.equal((await page.request.get(url, { headers: { [key]: "foreign" } })).status(), 404)
    }
  }

  for (const mode of ["failure", "timeout"]) {
    await enqueueMotion()
    const failed = await performMotion(mode)
    assert.equal(failed.status, "failed")
    assert(!failed.video && failed.project)
    assert.equal(failed.error_message.phase, "render")
    assert.equal(failed.error_message.command, "render")
    assert.equal(failed.error_message.reason, mode === "timeout" ? "timeout" : "protocol_error")
    assert.match(failed.error_message.detail, /editable project was created, but the video render failed/)
    if (mode === "timeout") assert.match(failed.broadcasts.join("\n"), /progress value="25"/)
    else assert.match(failed.error_message.stderr, /fixture video encoder failed/)
    const project = statusPanel.getByRole("link", { name: "Download project" })
    await project.waitFor()
    assert.equal(await statusPanel.getByRole("link", { name: "Download video" }).count(), 0)
    assert.equal((await page.request.get(origin + await project.getAttribute("href"))).status(), 200)
    assert.equal((await page.request.get(origin + `${root}/runs/${failed.id}/download`)).status(), 404)
  }
  await enqueueMotion()
  const recipeFailure = await performMotion("recipe")
  assert.equal(recipeFailure.status, "failed")
  assert(!recipeFailure.video && !recipeFailure.project)
  assert.equal(recipeFailure.error_message.phase, "recipe")
  assert.equal(recipeFailure.error_message.command, "start")
  assert.match(recipeFailure.error_message.detail, /Recipe execution failed/)
  await statusPanel.getByText(/Recipe execution failed/).waitFor()
  assert.equal(await statusPanel.getByRole("link", { name: "Download project" }).count(), 0)
  assert.equal((await (await page.request.get(origin + "/run-fixture-check")).json()).temporary_inputs, 0)
  assert.deepEqual(errors, [])
  console.log("PASS PhotoCraft byte parity, queued H.264 and editable project downloads, ownership, render failure and timeout salvage, progress, and temp cleanup")
} finally {
  await browser.close()
}
