# robot_lab's own config layer has no working "project config file" step
# despite what its defaults.yml header comment claims (myway_config only
# ships a defaults loader and an XDG loader -- confirmed by reading its
# source, not guessed) -- so this is set directly via RubyLLM.configure,
# which runs after robot_lab's own gem-load-time config application and
# layers on top of it rather than replacing it.
RubyLLM.configure do |config|
  # /v1 is required -- RubyLLM's Ollama provider (a thin OpenAI subclass) has
  # no fallback for this the way OpenAI's own provider does (its api_base
  # defaults to "https://api.openai.com/v1"); Ollama's own OpenAI-compat
  # server only listens on /v1/chat/completions, not bare /chat/completions.
  config.ollama_api_base = ENV.fetch("ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE", "http://localhost:11434/v1")

  # RubyLLM does not auto-populate this from ENV the way it does for some
  # other providers -- OpenRouter::configuration_requirements demands it be
  # set explicitly or every openrouter request fails auth.
  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
end
