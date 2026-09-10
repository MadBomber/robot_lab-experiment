import { Controller } from "@hotwired/stimulus"

// Live "agent working" readout with no polling endpoint: the elapsed clock
// ticks locally from the server-rendered conversation start time, and the
// message count starts at the server-rendered value and increments as the
// existing Turbo Stream broadcast appends rows into the transcript
// scroller's content element.
export default class extends Controller {
  static values = { startedAt: String, count: Number }
  static targets = ["elapsed", "count"]

  connect() {
    this.startedAtMs = Date.parse(this.startedAtValue)
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)

    const transcript = document.getElementById("transcript-messages")
    if (transcript) {
      this.observer = new MutationObserver((mutations) => this.rowsAppended(mutations))
      this.observer.observe(transcript, { childList: true })
    }
  }

  disconnect() {
    clearInterval(this.timer)
    this.observer?.disconnect()
  }

  rowsAppended(mutations) {
    const added = mutations.flatMap((m) => [...m.addedNodes]).filter((n) => n.nodeType === Node.ELEMENT_NODE).length
    if (added === 0) return

    this.countValue += added
    if (this.hasCountTarget) this.countTarget.textContent = this.countValue
  }

  tick() {
    if (!this.hasElapsedTarget || Number.isNaN(this.startedAtMs)) return

    const seconds = Math.max(0, Math.floor((Date.now() - this.startedAtMs) / 1000))
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    this.elapsedTarget.textContent = `${m}:${String(s).padStart(2, "0")}`
  }
}
