import { Controller } from "@hotwired/stimulus"

// Keeps each project's LLM model <select> in sync with its provider <select>.
// Attach to a container wrapping one or more provider/model form pairs; the
// full provider->models catalog rides the options value once, not per form.
export default class extends Controller {
  static values = { options: Object }

  providerChanged(event) {
    const providerSelect = event.target
    const form = providerSelect.closest("form")
    if (!form) return

    const modelSelect = form.querySelector("select[name='project[llm_model]']")
    if (!modelSelect) return

    const models = this.optionsValue[providerSelect.value] || []
    modelSelect.innerHTML = ""

    if (!providerSelect.value) {
      modelSelect.disabled = true
      modelSelect.appendChild(new Option("App default", ""))
      return
    }

    modelSelect.disabled = false
    models.forEach((m) => modelSelect.appendChild(new Option(m.label, m.value)))
  }
}
