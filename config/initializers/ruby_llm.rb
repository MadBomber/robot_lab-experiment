# robot_lab's own config layer has no working "project config file" step
# despite what its defaults.yml header comment claims (myway_config only
# ships a defaults loader and an XDG loader -- confirmed by reading its
# source, not guessed) -- so this is set directly via RubyLLM.configure,
# which runs after robot_lab's own gem-load-time config application and
# layers on top of it rather than replacing it.
RubyLLM.configure do |config|
  # Local model servers (see the provider gems in the Gemfile). Each provider
  # already defaults to its local server -- LM Studio at
  # http://localhost:1234/v1, apfel at http://127.0.0.1:11434/v1 -- so these
  # only override when the env var is set.
  config.lms_api_base   = ENV["ROBOT_LAB_RUBY_LLM__LMS_API_BASE"]   if ENV["ROBOT_LAB_RUBY_LLM__LMS_API_BASE"]
  config.apfel_api_base = ENV["ROBOT_LAB_RUBY_LLM__APFEL_API_BASE"] if ENV["ROBOT_LAB_RUBY_LLM__APFEL_API_BASE"]

  # RubyLLM does not auto-populate this from ENV the way it does for some
  # other providers -- OpenRouter::configuration_requirements demands it be
  # set explicitly or every openrouter request fails auth.
  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
end
