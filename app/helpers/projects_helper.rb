module ProjectsHelper
  # The provider and model halves of the LLM combobox value travel as one
  # "provider|model" string (model ids contain "/", never "|");
  # ProjectsController#llm_params splits on the same separator.
  LLM_CHOICE_SEPARATOR = "|".freeze

  # True when the project has no override, or its override still appears in
  # the live options list. False means the combobox's real options can't
  # represent the stored value (e.g. the model rolled off RubyLLM's registry,
  # or the project's Ollama server no longer has it pulled) -- the caller
  # should inject a synthetic option rather than let the picker silently
  # fall back to "App default" while the DB still holds an override.
  def current_llm_pair_listed?(project, options)
    return true unless project.llm_provider?

    options.any? { |option| option[:provider] == project.llm_provider && option[:model] == project.llm_model }
  end

  # The project's stored override as a combobox value -- "" (no committed
  # option, so the "App default" placeholder shows) when there is none.
  def llm_choice_value(project)
    return "" unless project.llm_provider?

    "#{project.llm_provider}#{LLM_CHOICE_SEPARATOR}#{project.llm_model}"
  end

  # The live options as { provider => [[label, "provider|model"], ...] },
  # ready for the combobox's grouped items.
  def llm_choice_groups(options)
    options.group_by { |option| option[:provider] }.transform_values { |group| llm_choices(group) }
  end

  # One provider's options as the combobox's [label, value] pairs.
  def llm_choices(provider_options)
    provider_options.map do |option|
      [option[:label], "#{option[:provider]}#{LLM_CHOICE_SEPARATOR}#{option[:model]}"]
    end
  end
end
