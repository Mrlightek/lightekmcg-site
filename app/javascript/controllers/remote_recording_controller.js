import { Controller } from "@hotwired/stimulus"

const MIME_TYPE = "video/webm"
const MAX_BYTES = 5 * 1024 * 1024
const MAX_DURATION_MS = 60_000

export default class extends Controller {
  static targets = ["consent", "start", "save", "revoke", "notice", "playback"]
  static values = { role: String, consent: String, start: String, upload: String, revoke: String }

  connect() {
    this.update({})
  }

  disconnect() {
    this.discard()
  }

  update(event) {
    const { recording, stream } = event.detail || {}
    if (stream !== undefined) {
      this.stream = stream
      if (!stream) this.discard()
    }
    if (recording) this.recording = recording
    const state = this.recording || {}
    if (state.revoked) this.discard()

    this.consentTarget.disabled = Boolean(state.revoked || state[this.roleValue] || this.pending)
    this.startTarget.hidden = this.roleValue !== "customer"
    this.startTarget.disabled = !state.customer || !state.technician || state.started || state.revoked ||
      !this.recordable() || this.pending
    this.saveTarget.hidden = !this.recorder || this.recorder.state !== "recording"
    this.revokeTarget.disabled = Boolean(state.revoked || (!state.customer && !state.technician))
    this.playbackTarget.hidden = !state.saved || state.revoked

    if (state.revoked) this.noticeTarget.textContent = "Recording permission was withdrawn."
    else if (this.recorder?.state === "recording") this.noticeTarget.textContent = "Recording in progress."
    else if (state.saved) this.noticeTarget.textContent = "A recording is available."
    else if (state.started) this.noticeTarget.textContent = "The customer started a recording."
    else if (state[this.roleValue] && !(state.customer && state.technician)) this.noticeTarget.textContent = "Waiting for the other participant to approve recording."
    else if (state.customer && state.technician && !state.started) {
      this.noticeTarget.textContent = "Both participants agreed. The customer can record a shared browser tab."
    }
  }

  recordable() {
    return typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(MIME_TYPE) &&
      this.stream?.getVideoTracks()[0]?.getSettings().displaySurface === "browser"
  }

  async consent() {
    try {
      const response = await this.request(this.consentValue)
      this.update({ detail: { recording: await response.json() } })
    } catch {
      this.noticeTarget.textContent = "Recording consent could not be saved."
    }
  }

  async start() {
    if (!this.recordable() || this.pending || this.recorder) return

    this.pending = true
    this.update({})
    const stream = this.stream
    try {
      const recorder = new MediaRecorder(new MediaStream(stream.getVideoTracks()), {
        mimeType: MIME_TYPE, videoBitsPerSecond: 400_000
      })
      await this.request(this.startValue)
      if (stream !== this.stream || this.recording?.revoked) return

      this.recorder = recorder
      this.chunks = []
      this.byteSize = 0
      recorder.ondataavailable = event => {
        if (this.recorder !== recorder || !event.data.size) return
        this.byteSize += event.data.size
        if (this.byteSize <= MAX_BYTES) this.chunks.push(event.data)
        else this.discard("Recording exceeded 5 MB and was discarded.")
      }
      recorder.onstop = () => this.upload(recorder)
      recorder.onerror = () => this.discard("The browser could not record this tab.")
      recorder.start(1000)
      this.timer = window.setTimeout(() => this.save(), MAX_DURATION_MS)
      this.update({ detail: { recording: { ...this.recording, started: true } } })
    } catch {
      this.noticeTarget.textContent = "Recording could not start. Connect the technician and share a browser tab."
    } finally {
      this.pending = false
      this.update({})
    }
  }

  save() {
    if (this.recorder?.state === "recording") this.recorder.stop()
  }

  async upload(recorder) {
    if (this.recorder !== recorder) return

    const blob = new Blob(this.chunks, { type: MIME_TYPE })
    this.discard()
    if (!blob.size) return
    const body = new FormData()
    body.append("support_recording", blob, "session.webm")
    const upload = new AbortController()
    this.uploadRequest = upload
    this.noticeTarget.textContent = "Saving recording…"
    try {
      await this.request(this.uploadValue, { body, signal: upload.signal })
      this.update({ detail: { recording: { ...this.recording, saved: true } } })
    } catch {
      if (!upload.signal.aborted) this.noticeTarget.textContent = "Recording could not be saved."
    } finally {
      if (this.uploadRequest === upload) this.uploadRequest = null
    }
  }

  async revoke() {
    this.discard()
    try {
      await this.request(this.revokeValue, { method: "DELETE" })
      this.update({ detail: { recording: { ...this.recording, revoked: true } } })
    } catch {
      this.noticeTarget.textContent = "Permission could not be withdrawn on the server. Try again."
    }
  }

  discard(message) {
    window.clearTimeout(this.timer)
    this.uploadRequest?.abort()
    const recorder = this.recorder
    this.recorder = null
    this.chunks = []
    if (recorder?.state === "recording") recorder.stop()
    if (this.hasSaveTarget) this.saveTarget.hidden = true
    if (message && this.hasNoticeTarget) this.noticeTarget.textContent = message
  }

  async request(url, { method = "POST", body, signal } = {}) {
    const response = await fetch(url, {
      method, body, signal, redirect: "error", cache: "no-store",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      }
    })
    if (!response.ok) throw new Error("Recording request denied")
    return response
  }
}
