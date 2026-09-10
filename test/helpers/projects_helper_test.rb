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

  test "llm_choice_value combines the override as provider|model" do
    project = Project.new(llm_provider: "openrouter", llm_model: "moonshotai/kimi-k2")
    assert_equal "openrouter|moonshotai/kimi-k2", llm_choice_value(project)
  end

  test "llm_choice_value is blank when the project has no override" do
    assert_equal "", llm_choice_value(Project.new)
  end

  test "llm_choice_groups groups [label, value] pairs by provider" do
    options = [
      { provider: "ollama", model: "qwen3.6:latest", label: "Ollama - qwen3.6:latest" },
      { provider: "openrouter", model: "moonshotai/kimi-k2", label: "OpenRouter - Kimi K2" }
    ]

    groups = llm_choice_groups(options)

    assert_equal %w[ollama openrouter], groups.keys
    assert_equal [["Ollama - qwen3.6:latest", "ollama|qwen3.6:latest"]], groups["ollama"]
    assert_equal [["OpenRouter - Kimi K2", "openrouter|moonshotai/kimi-k2"]], groups["openrouter"]
  end
end
