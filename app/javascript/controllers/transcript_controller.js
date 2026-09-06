import { Controller } from "@hotwired/stimulus"

// Bulk-collapses the transcript's disclosure rows (tool calls, tool results,
// thinking) from the "Collapse tool calls" toggle. Rows are native <details>
// elements so they stay usable with zero JS; this controller only drives the
// all-at-once gesture.
export default class extends Controller {
  static targets = ["details"]

  syncCollapsed(event) {
    // poetry:toggle:change fires BEFORE the flip renders; detail.pressed is
    // the state the toggle is about to enter.
    const pressed = Boolean(event.detail?.pressed)
    this.detailsTargets.forEach((details) => { details.open = !pressed })
  }
}
