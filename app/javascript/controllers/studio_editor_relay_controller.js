import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]
  static values = { origin: String, engine: String, catalog: String, apply: String }

  connect() {
    this.open()
  }

  disconnect() {
    this.close()
  }

  close() {
    this.port?.close()
    this.controller?.abort()
  }

  open() {
    this.close()
    this.controller = new AbortController()
    this.pending = false
    this.features = new Set()
    this.files = new Map()
    this.statusUrl = null
    const channel = new MessageChannel()
    this.port = channel.port1
    this.port.onmessage = (event) => this.receive(event.data, channel.port1, this.controller.signal)
    this.frameTarget.contentWindow.postMessage({ name: "lightek-studio-features-v1", engine: this.engineValue },
      this.originValue, [channel.port2])
  }

  async receive(message, port, signal) {
    if (port !== this.port || !message || this.pending || !Number.isSafeInteger(message.id)) return
    this.pending = true
    const send = (payload) => {
      if (!signal.aborted) port.postMessage({ requestId: message.id, ...payload })
    }
    try {
      switch (message.kind) {
        case "catalog": {
          const response = await this.request(this.catalogValue, signal)
          const catalog = await response.json()
          if (!response.ok) throw new Error("Studio features are unavailable.")
          this.features = new Set(catalog.features.map((feature) => feature.id))
          send(catalog)
          break
        }
        case "apply": {
          if (!this.features.has(message.feature) || !(message.file instanceof File) || message.file.size > 20 * 1024 * 1024) {
            throw new Error("Choose a published Studio feature and an export up to 20 MiB.")
          }
          // The cross-origin frame owns the editor API. Its port returns the selected snapshot.
          if (message.snapshot_source === "bridge-v1" &&
              (this.engineValue !== "photocraft" || message.file.name !== "studio-snapshot.pcraft")) {
            throw new Error("Invalid PhotoCraft bridge snapshot.")
          }
          this.files.clear()
          this.statusUrl = null
          const assets = message.assets || []
          if (!Array.isArray(assets) || assets.length > 120 ||
              assets.some((asset) => !asset || typeof asset.path !== "string" || !(asset.file instanceof File)) ||
              assets.reduce((total, asset) => total + asset.file.size, 0) > 100 * 1024 * 1024) {
            throw new Error("Invalid EffectCraft asset transfer.")
          }
          const body = new FormData()
          body.append("editor", this.engineValue)
          body.append("input_file", message.file)
          if (assets.length) {
            body.append("asset_paths", JSON.stringify(assets.map(({ path }) => path)))
            for (const { file } of assets) body.append("assets[]", file)
          }
          for (const key of ["context", "parameters", "inputs"]) body.append(key, JSON.stringify(message[key]))
          const response = await this.request(this.applyValue.replace("studio.operation_placeholder", message.feature), signal, { method: "POST", body })
          send(await this.result(response))
          break
        }
        case "status": {
          if (!this.statusUrl) throw new Error("This render is no longer being tracked.")
          const response = await this.request(this.statusUrl, signal)
          send(await this.result(response))
          break
        }
        case "download": {
          if (!this.files.has(message.file)) throw new Error("This output is unavailable.")
          const response = await this.request(this.files.get(message.file), signal)
          if (!response.ok) throw new Error("Could not download the result.")
          send({ blob: await response.blob() })
          break
        }
      }
    } catch (error) {
      send({ relay_error: error.message })
    } finally {
      if (port === this.port) this.pending = false
    }
  }

  request(path, signal, options = {}) {
    const url = new URL(path, location.origin)
    if (url.origin !== location.origin || !url.pathname.startsWith("/studio/macro_maker/")) {
      throw new Error("Invalid Studio endpoint.")
    }
    const headers = { Accept: "application/json" }
    if (options.method === "POST") headers["X-CSRF-Token"] = document.querySelector('meta[name="csrf-token"]')?.content || ""
    return fetch(url, { ...options, signal, headers, credentials: "same-origin", redirect: "error" })
  }

  async result(response) {
    if (![200, 202, 422].includes(response.status)) throw new Error("Studio rejected this request.")
    const { status_url, download_url, project_download_url, ...result } = await response.json()
    if (status_url) this.statusUrl = status_url
    if (download_url) this.files.set("output", download_url)
    if (project_download_url) this.files.set("project", project_download_url)
    return { ...result, output: this.files.has("output"), project: this.files.has("project") }
  }
}
