import { Controller } from "@hotwired/stimulus"

// Polls the task heartbeat endpoint while an agent run is live, keeping the
// elapsed clock and message count fresh between Turbo Stream broadcasts.
// The controller only renders (and therefore only polls) while the
// agent-status partial is in its running state.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 2000 } }
  static targets = ["elapsed", "count"]

  connect() {
    this.lastMessageCount = null
    this.poll()
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const res = await fetch(this.urlValue)
      if (!res.ok) return
      const data = await res.json()
      if (!data.started_at) return // no active conversation

      const elapsedSecs = Math.floor((Date.now() - new Date(data.started_at).getTime()) / 1000)
      if (this.hasElapsedTarget) this.elapsedTarget.textContent = this.formatElapsed(elapsedSecs)

      if (this.hasCountTarget && data.message_count !== this.lastMessageCount) {
        this.lastMessageCount = data.message_count
        this.countTarget.textContent = data.message_count
      }
    } catch {
      // Silently fail -- never break the page over a missed heartbeat.
    }
  }

  formatElapsed(seconds) {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return `${m}:${String(s).padStart(2, "0")}`
  }
}
