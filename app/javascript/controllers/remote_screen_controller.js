import { Controller } from "@hotwired/stimulus"

const POLL_MS = 2500
const LEASE_MS = 8500
const NETWORK_TIMEOUT_MS = 4500

export default class extends Controller {
  static targets = ["start", "status", "video", "fullscreen"]
  static values = { role: String, exchange: String, end: String }

  connect() {
    this.stopOnNavigation = () => this.close()
    window.addEventListener("pagehide", this.stopOnNavigation)
    document.addEventListener("turbo:before-cache", this.stopOnNavigation)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.stopOnNavigation)
    document.removeEventListener("turbo:before-cache", this.stopOnNavigation)
    this.close()
  }

  async start() {
    if (this.attempt) return

    const attempt = new AbortController()
    this.attempt = attempt
    this.startTarget.disabled = true
    const sharing = this.roleValue === "customer"
    try {
      if (sharing) {
        const stream = await navigator.mediaDevices.getDisplayMedia({
          audio: false,
          video: { width: { ideal: 1920 }, height: { ideal: 1080 }, frameRate: { ideal: 15, max: 20 } }
        })
        if (attempt.signal.aborted) {
          stream.getTracks().forEach(track => track.stop())
          return
        }
        this.stream = stream
        stream.getVideoTracks()[0].addEventListener("ended", () => this.finish("Screen sharing stopped."), { once: true })
      }

      const initial = await this.exchange({ ice: true }, attempt)
      const connection = new RTCPeerConnection({ iceServers: initial.ice_servers })
      this.peer = connection
      connection.onconnectionstatechange = () => this.connectionChanged(connection)
      if (sharing) {
        const track = this.stream.getVideoTracks()[0]
        track.contentHint = "detail"
        connection.addTransceiver(track, { direction: "sendonly", sendEncodings: [{ maxBitrate: 2500000 }] })
        this.display(this.stream)
        this.statusTarget.textContent = "Screen selected. Waiting for the technician to connect."
        const offer = await connection.createOffer()
        const sdp = await this.description(connection, offer, attempt.signal)
        await this.exchange({ screen_sdp: sdp }, attempt)
      } else {
        connection.ontrack = event => this.display(new MediaStream([event.track]))
        this.statusTarget.textContent = "Waiting for the customer to choose a screen."
      }
      await this.poll(attempt)
    } catch (error) {
      if (attempt.signal.aborted) return
      if (error.name === "NotAllowedError" && !this.stream) {
        this.close("Screen selection was cancelled.")
        this.startTarget.disabled = false
      } else {
        this.finish("The connection could not be established. Open a new request to try again.")
      }
    }
  }

  async poll(attempt) {
    const state = await this.exchange({}, attempt)
    const connection = this.peer
    if (state.sdp && !connection.remoteDescription) {
      if (this.roleValue === "customer") {
        await connection.setRemoteDescription({ type: "answer", sdp: state.sdp })
      } else {
        await connection.setRemoteDescription({ type: "offer", sdp: state.sdp })
        const answer = await connection.createAnswer()
        const sdp = await this.description(connection, answer, attempt.signal)
        await this.exchange({ screen_sdp: sdp }, attempt)
      }
    }
    this.pollTimer = window.setTimeout(() => {
      this.poll(attempt).catch(() => {
        if (!attempt.signal.aborted) this.finish("Screen sharing ended or authorization could not be verified.")
      })
    }, POLL_MS)
  }

  async exchange(payload, attempt) {
    const result = await fetch(this.exchangeValue, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify(payload),
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.any([attempt.signal, AbortSignal.timeout(NETWORK_TIMEOUT_MS)])
    })
    if (!result.ok) throw new Error("Screen-sharing authorization is unavailable")

    const data = await result.json()
    attempt.signal.throwIfAborted()
    this.refreshLease(data.valid_for_ms)
    return data
  }

  async description(connection, description, signal) {
    await connection.setLocalDescription(description)
    if (connection.iceGatheringState !== "complete") {
      await new Promise((resolve, reject) => {
        const gather = () => {
          if (connection.iceGatheringState !== "complete") return
          cleanup()
          resolve()
        }
        const abort = () => {
          cleanup()
          reject(signal.reason)
        }
        const cleanup = () => {
          connection.removeEventListener("icegatheringstatechange", gather)
          signal.removeEventListener("abort", abort)
        }
        signal.throwIfAborted()
        connection.addEventListener("icegatheringstatechange", gather)
        signal.addEventListener("abort", abort, { once: true })
        gather()
      })
    }
    return connection.localDescription.sdp
  }

  refreshLease(validForMs) {
    window.clearTimeout(this.leaseTimer)
    this.leaseTimer = window.setTimeout(() => this.finish("Screen sharing stopped because authorization could not be renewed."), Math.min(LEASE_MS, validForMs))
  }

  connectionChanged(connection) {
    const state = connection.connectionState
    if (state === "connected") this.statusTarget.textContent = "Screen sharing is active."
    if (state === "disconnected") this.statusTarget.textContent = "Connection interrupted. Waiting for the network to recover."
    if (state === "failed") this.finish("The screen connection failed. Open a new request to reconnect.")
  }

  display(stream) {
    this.videoTarget.srcObject = stream
    this.videoTarget.hidden = false
    this.fullscreenTarget.hidden = !document.fullscreenEnabled
  }

  fullscreen() {
    this.videoTarget.requestFullscreen().catch(() => {})
  }

  end(event) {
    event.preventDefault()
    this.finish("Screen sharing ended.")
  }

  async finish(message) {
    this.close(message)
    this.startTarget.disabled = true
    try {
      const response = await fetch(this.endValue, {
        method: "DELETE",
        headers: this.headers(),
        redirect: "error",
        signal: AbortSignal.timeout(NETWORK_TIMEOUT_MS)
      })
      if (!response.ok) throw new Error("Could not confirm session end")
    } catch {
      if (this.hasStatusTarget) this.statusTarget.textContent = "The local connection is closed. Reload when online to confirm the session ended."
    }
  }

  close(message) {
    this.attempt?.abort()
    this.attempt = null
    window.clearTimeout(this.pollTimer)
    window.clearTimeout(this.leaseTimer)
    this.peer?.close()
    this.peer = null
    this.stream?.getTracks().forEach(track => track.stop())
    this.stream = null
    if (this.hasVideoTarget) {
      this.videoTarget.srcObject = null
      this.videoTarget.hidden = true
    }
    if (this.hasFullscreenTarget) this.fullscreenTarget.hidden = true
    if (message && this.hasStatusTarget) this.statusTarget.textContent = message
  }

  headers() {
    return {
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
    }
  }
}
