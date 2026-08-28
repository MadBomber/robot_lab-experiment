require "test_helper"

class ProjectsHelperTest < ActionView::TestCase
  include ProjectsHelper

  test "current_llm_pair_listed? is true when the project has no override" do
    project = Project.new
    assert current_llm_pair_listed?(project, [])
  end

  test "current_llm_pair_listed? is true when the override matches an available option" do
    project = Project.new(llm_provider: "ollama", llm_model: "qwen3.6:latest")
    options = [{ provider: "ollama", model: "qwen3.6:latest", label: "Ollama - qwen3.6:latest" }]
    assert current_llm_pair_listed?(project, options)
  end

  test "current_llm_pair_listed? is false when the override no longer appears in the live options" do
    project = Project.new(llm_provider: "openrouter", llm_model: "retired/model")
    options = [{ provider: "openrouter", model: "moonshotai/kimi-k2", label: "OpenRouter - Kimi K2" }]
    assert_not current_llm_pair_listed?(project, options)
  end

  test "current_llm_provider_listed? is false when the provider itself isn't offered at all" do
    project = Project.new(llm_provider: "azure", llm_model: "gpt-4o")
    options = [{ provider: "openrouter", model: "moonshotai/kimi-k2", label: "OpenRouter - Kimi K2" }]
    assert_not current_llm_provider_listed?(project, options)
  end

  test "llm_options_for_provider returns only that provider's options" do
    project = Project.new(llm_provider: "ollama")
    options = [
      { provider: "ollama", model: "qwen3.6:latest", label: "Ollama - qwen3.6:latest" },
      { provider: "openrouter", model: "moonshotai/kimi-k2", label: "OpenRouter - Kimi K2" }
    ]
    assert_equal [options.first], llm_options_for_provider(project, options)
  end

  test "llm_options_for_provider is empty when the project has no override" do
    assert_equal [], llm_options_for_provider(Project.new, [{ provider: "ollama", model: "x", label: "x" }])
  end
end
