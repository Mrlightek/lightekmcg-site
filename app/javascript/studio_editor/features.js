import { readMacroField } from "../macro_maker/form_values.js"

function photoContext(snapshot) {
  return snapshot.slice(0, 30).arrayBuffer().then(async (buffer) => {
    const context = { open_document: snapshot.size > 0 }
    if (!snapshot.name.toLowerCase().endsWith(".pcraft")) return context
    if (buffer.byteLength < 30) throw new Error("Choose a valid PhotoCraft export.")
    const header = new DataView(buffer)
    const nameSize = header.getUint16(26, true)
    const offset = 30 + nameSize + header.getUint16(28, true)
    const bytes = header.getUint32(18, true)
    const size = header.getUint32(22, true)
    const name = await snapshot.slice(30, 30 + nameSize).text()
    if (header.getUint32(0, true) !== 0x04034b50 || name !== "manifest.json" || !size ||
        size > 4 * 1024 * 1024 || !bytes || offset + bytes > snapshot.size) {
      throw new Error("Could not read the PhotoCraft export manifest.")
    }
    let payload = snapshot.slice(offset, offset + bytes)
    const compression = header.getUint16(8, true)
    if (compression === 8) {
      const decoder = payload.stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader()
      const chunks = []
      let decoded = 0
      try {
        for (;;) {
          const { value, done } = await decoder.read()
          if (done) break
          decoded += value.length
          if (decoded > size) throw new Error("Invalid PhotoCraft manifest size.")
          chunks.push(value)
        }
      } finally {
        await decoder.cancel()
      }
      payload = new Blob(chunks)
    } else if (compression !== 0) {
      throw new Error("Unsupported PhotoCraft export compression.")
    }
    const { document } = JSON.parse(await payload.text())
    if (!document || !document.size || !Number.isInteger(document.size.width)) throw new Error("Choose a valid PhotoCraft export.")
    const active = Boolean(document.selection)
    return { ...context, active_selection: active, selection_or_mask: active }
  })
}

function photoBridge() {
  const bridge = window.photocraftBridge
  return bridge?.version === 1 && typeof bridge.exportBytes === "function" ? bridge : null
}

async function exportPhoto(bridge) {
  const bytes = await bridge.exportBytes("pcraft")
  if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > 20 * 1024 * 1024) {
    throw new Error("PhotoCraft must return a non-empty .pcraft export up to 20 MiB.")
  }
  return new File([bytes], "studio-snapshot.pcraft", { type: "application/octet-stream" })
}

const motion = {
  async context() {
    const state = await window.effectcraft.inspect()
    const composition = Number.isInteger(state.activeComp) && state.activeComp > 0
    return { open_composition: composition, timeline_playhead: composition && Number.isFinite(state.time),
      selected_layer: state.selectedLayers?.length > 0 }
  },
  async exportFile() {
    const path = `/lightek-studio-${crypto.randomUUID()}.ecproj`
    await window.effectcraft.execute("file.saveCopy", { path })
    const bytes = window.effectcraft.readFile(path)
    if (!bytes?.length) throw new Error("EffectCraft did not export the project.")
    return new File([bytes], "studio-export.ecproj", { type: "application/octet-stream" })
  },
  async assets(file) {
    const project = JSON.parse(await file.text())
    const paths = new Set()
    for (const item of Object.values(project.items || {})) {
      for (const footage of [item.kind?.type === "Footage" ? item.kind : null, item.proxy?.footage]) {
        if (!footage) continue
        if (footage.path && !(footage.kind === "Data" && typeof footage.data === "string")) paths.add(footage.path)
        for (const frame of footage.sequence || []) paths.add(frame)
      }
    }

    const files = new Map(window.effectcraft.files().map(({ path, size }) => [path, size]))
    let total = 0
    const assets = []
    for (const path of paths) {
      const localPath = files.has(path) ? path : `/${path.replace(/^\.\//, "")}`
      const size = files.get(localPath)
      if (!size) continue // The server reports the exact missing project paths.
      total += size
      if (assets.length >= 120 || total > 100 * 1024 * 1024) throw new Error("EffectCraft transfers are limited to 120 files and 100 MiB.")
      const bytes = window.effectcraft.readFile(localPath)
      if (bytes?.length) assets.push({ path, file: new File([bytes], "asset") })
    }
    return assets
  },
  openFile(file) { return window.effectcraft.addFile(file) }
}

function download(file) {
  const url = URL.createObjectURL(file)
  const anchor = document.createElement("a")
  anchor.href = url
  anchor.download = file.name
  anchor.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

function showErrors(container, result) {
  const step = result.error
  const issues = result.errors || step?.errors || (step ? [step] : [])
  const messages = issues.map((issue) => [
    issue.step_index == null ? null : `Step ${issue.step_index}`,
    issue.command, issue.reason || issue.kind, issue.detail, issue.stderr
  ].filter(Boolean).join(" · "))
  container.textContent = messages.join("\n") || result.relay_error || "The Studio feature could not run."
}

function connectFeatures(engine, port) {
  const image = engine === "photocraft"
  document.querySelector("#lightek-studio-features")?.remove()
  const panel = document.createElement("details")
  panel.id = "lightek-studio-features"
  panel.style.cssText = "position:fixed;top:3rem;right:1rem;z-index:2147483647;max-width:27rem;max-height:80vh;overflow:auto;background:#1b2028;color:#f2f3f5;padding:0.75rem;font:14px system-ui;border:1px solid #576477;border-radius:6px"
  panel.innerHTML = `<summary>Studio Features</summary><form>
    <p><label for="studio-feature-choice">Feature</label> <select id="studio-feature-choice"><option value="">Choose a feature</option></select></p>
    <div data-photo hidden>
      <p data-photo-instructions>Upload a PhotoCraft .pcraft snapshot or a flat image. A .pcraft file preserves an active selection.</p>
      <p><label>PhotoCraft file <input type="file" accept=".pcraft,image/png,image/jpeg,image/webp"></label></p>
    </div>
    <section data-fields></section>
    <p data-context></p>
    <button type="submit" disabled>Run</button>
    <p role="status" data-status style="white-space:pre-wrap"></p>
    <section data-downloads></section>
  </form>`
  document.body.append(panel)
  const find = (selector) => panel.querySelector(selector)
  const chooser = find("select")
  const form = find("form")
  const fields = find("[data-fields]")
  const contextNote = find("[data-context]")
  const status = find("[data-status]")
  const downloads = find("[data-downloads]")
  const run = find('button[type="submit"]')
  const fileField = find('input[type="file"]')
  find("[data-photo]").hidden = !image
  const features = new Map()
  const forms = new Map()
  let nextId = 0
  let busy = false
  let snapshot = null
  let snapshotContext = {}
  let original = null
  let openedResult = false
  let timer
  const waiting = new Map()
  port.onmessage = ({ data }) => waiting.get(data.requestId)?.(data)
  const call = (kind, args = {}) => new Promise((resolve, reject) => {
    const id = ++nextId
    const timeout = setTimeout(() => {
      waiting.delete(id)
      reject(new Error("The Studio request timed out."))
    }, 35000)
    waiting.set(id, (result) => {
      clearTimeout(timeout)
      waiting.delete(id)
      if (result.relay_error) reject(new Error(result.relay_error))
      else resolve(result)
    })
    port.postMessage({ id, kind, ...args })
  })
  const currentContext = async () => {
    if (!image) return motion.context()
    return snapshotContext
  }
  const missing = (feature, context) => feature.requires.filter((flag) => context[flag] !== true)
  async function refresh() {
    const choice = chooser.value
    const feature = features.get(choice)
    if (busy || !panel.open || !feature) return
    if (image) {
      const bridge = photoBridge()
      find("[data-photo-instructions]").textContent = bridge
        ? "Run uses the current PhotoCraft document. Choose a file below to use it instead."
        : "Upload a PhotoCraft .pcraft snapshot or a flat image. A .pcraft file preserves an active selection."
      if (bridge && !snapshot) {
        contextNote.textContent = feature.requires.length ? "Studio checks the active document when you run the feature." : ""
        run.disabled = false
        return
      }
    }
    let context = {}
    try { context = await currentContext() } catch { /* unavailable context stays false */ }
    if (busy || choice !== chooser.value) return
    const absent = missing(feature, context)
    contextNote.textContent = absent.length ? `This operation requires ${absent.map((flag) => flag.replaceAll("_", " ")).join(", ")}.` : ""
    run.disabled = absent.length > 0 || (image ? !context.open_document : !context.open_composition)
  }
  chooser.onchange = () => {
    if (fields.firstChild) fields.firstChild.remove()
    const feature = features.get(chooser.value)
    if (feature) {
      if (!forms.has(feature.id)) {
        const wrapper = document.createElement("div")
        wrapper.innerHTML = feature.fields
        forms.set(feature.id, wrapper)
      }
      fields.append(forms.get(feature.id))
    }
    run.disabled = true
    contextNote.textContent = ""
    refresh()
  }
  fields.addEventListener("input", ({ target }) => {
    if (target.matches("[data-color-picker]")) {
      const hex = target.closest("[data-macro-field]")?.querySelector("[data-literal-value]")
      if (hex) hex.value = target.value
    }
  })
  async function setPhotoSnapshot(file) {
    snapshot = file
    snapshotContext = {}
    run.disabled = true
    try {
      const context = file ? await photoContext(file) : {}
      if (file === snapshot) snapshotContext = context
    } catch (error) {
      status.textContent = error.message
    }
    await refresh()
  }
  fileField.onchange = () => setPhotoSnapshot(fileField.files[0])
  function resultButton(label, action) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = label
    button.onclick = async () => {
      button.disabled = true
      try { await action() } catch (error) { status.textContent = error.message }
      finally { button.disabled = false }
    }
    downloads.append(button)
  }

  form.onsubmit = async (event) => {
    event.preventDefault()
    const feature = features.get(chooser.value)
    if (busy || !feature || run.disabled) return
    busy = true
    chooser.disabled = true
    run.disabled = true
    downloads.replaceChildren()
    const bridge = image && !snapshot && photoBridge()
    status.textContent = image && !bridge ? "Uploading PhotoCraft file…" : "Exporting document…"
    try {
      const photo = image ? (bridge ? await exportPhoto(bridge) : snapshot) : null
      const context = bridge ? await photoContext(photo) : await currentContext()
      const absent = missing(feature, context)
      if (absent.length) throw new Error(`This operation requires ${absent.map((flag) => flag.replaceAll("_", " ")).join(", ")}.`)
      const file = image ? photo : await motion.exportFile()
      if (!image) original = file
      const values = { params: [], inputs: [] }
      for (const field of fields.querySelectorAll("[data-macro-field]")) {
        const value = readMacroField(field)
        if (value !== undefined) values[field.dataset.group].push([field.dataset.fieldName, value])
      }
      const assets = image ? [] : await motion.assets(file)
      let result = await call("apply", { feature: feature.id, file, assets, context, ...(bridge ? { snapshot_source: "bridge-v1" } : {}),
        parameters: Object.fromEntries(values.params), inputs: Object.fromEntries(values.inputs) })
      while (result.status === "pending" || result.status === "running") {
        const percent = result.progress?.percent
        status.textContent = Number.isInteger(percent) ? `Rendering… ${percent}%` :
          (result.status === "pending" ? "Queued…" : "Rendering…")
        await new Promise((resolve) => setTimeout(resolve, 1000))
        result = await call("status")
      }
      if (result.status === "completed") {
        status.textContent = image ? "Complete. Download the PNG and open it in PhotoCraft as a new document." : "Complete."
      }
      else showErrors(status, result)
      if (result.output) {
        const resultFile = async () => {
          const { blob } = await call("download", { file: "output" })
          return new File([blob], image ? "studio-result.png" : "studio-result.mp4")
        }
        resultButton(image ? "Download image" : "Download video", async () => {
          download(await resultFile())
        })
      }
      if (result.project) {
        const resultProject = async () => new File([(await call("download", { file: "project" })).blob], "studio-result.ecproj")
        resultButton("Download project", async () => download(await resultProject()))
        resultButton("Open result as a new project", async () => {
          const file = await resultProject()
          if (!openedResult) original = await motion.exportFile()
          await motion.openFile(new File([file], `studio-result-${crypto.randomUUID()}.ecproj`))
          openedResult = true
        })
      }
    } catch (error) {
      status.textContent = error.message
    } finally {
      busy = false
      chooser.disabled = false
      refresh()
    }
  }

  const restore = document.createElement("button")
  restore.type = "button"
  restore.textContent = "Reopen original project snapshot"
  if (!image) form.append(restore)
  restore.onclick = async () => {
    if (!original || !openedResult || busy) return
    try {
      await motion.openFile(new File([original], `studio-original-${crypto.randomUUID()}.ecproj`))
      openedResult = false
    } catch (error) {
      status.textContent = error.message
    }
  }
  async function tick() {
    if (!panel.isConnected) return
    restore.hidden = !openedResult
    await refresh()
    timer = setTimeout(tick, 600)
  }
  tick()
  let loaded = false
  panel.ontoggle = async () => {
    if (!panel.open || loaded) return
    loaded = true
    try {
      for (const feature of (await call("catalog")).features) {
        features.set(feature.id, feature)
        chooser.add(new Option(feature.name, feature.id))
      }
    } catch (error) {
      loaded = false
      status.textContent = error.message
    }
  }
  return () => {
    clearTimeout(timer)
    panel.remove()
    port.close()
  }
}

export function installStudioFeatures({ parentOrigin, engine }) {
  let disconnect
  window.addEventListener("message", (event) => {
    if (event.source !== window.parent || event.origin !== parentOrigin ||
        event.data?.name !== "lightek-studio-features-v1" || event.data.engine !== engine || !event.ports[0]) return
    disconnect?.()
    disconnect = connectFeatures(engine, event.ports[0])
  })
}
