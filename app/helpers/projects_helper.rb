module ProjectsHelper
  # True when the project has no override, or its override still appears in
  # the live options list. False means the select's real <option> tags can't
  # represent the stored value (e.g. the model rolled off RubyLLM's registry,
  # or the project's Ollama server no longer has it pulled) -- the caller
  # should inject a synthetic option rather than let the browser silently
  # fall back to "App default" while the DB still holds an override.
  def current_llm_pair_listed?(project, options)
    return true unless project.llm_provider?

    options.any? { |o| o[:provider] == project.llm_provider && o[:model] == project.llm_model }
  end

  # Same idea as #current_llm_pair_listed?, but for the provider select --
  # true when the project has no override, or its provider is one of the
  # providers the live options actually cover.
  def current_llm_provider_listed?(project, options)
    return true unless project.llm_provider?

    options.any? { |o| o[:provider] == project.llm_provider }
  end

  # The project's own provider's options, grouped for the model <select> --
  # empty when the project has no override.
  def llm_options_for_provider(project, options)
    return [] unless project.llm_provider?

    options.select { |o| o[:provider] == project.llm_provider }
  end
end
