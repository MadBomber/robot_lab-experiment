require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("project_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "valid with a real git repo path" do
    project = Project.new(name: "Demo", repo_folder_path: @repo_dir)
    assert project.valid?
  end

  test "invalid when repo_folder_path is not a git repo" do
    non_repo = Dir.mktmpdir("not_a_repo")
    project = Project.new(name: "Demo", repo_folder_path: non_repo)

    assert_not project.valid?
    assert_includes project.errors[:repo_folder_path], "is not a git repository"
  ensure
    FileUtils.remove_entry(non_repo)
  end

  test "invalid without a name" do
    project = Project.new(repo_folder_path: @repo_dir)
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "repo_folder_path must be unique" do
    Project.create!(name: "First", repo_folder_path: @repo_dir)
    dup = Project.new(name: "Second", repo_folder_path: @repo_dir)

    assert_not dup.valid?
    assert_includes dup.errors[:repo_folder_path], "has already been taken"
  end

  test "effective_cwd is repo_folder_path when no subproject_path" do
    project = Project.new(repo_folder_path: @repo_dir)
    assert_equal @repo_dir, project.effective_cwd
  end

  test "effective_cwd appends subproject_path when present" do
    project = Project.new(repo_folder_path: @repo_dir, subproject_path: "packages/app")
    assert_equal File.join(@repo_dir, "packages/app"), project.effective_cwd
  end

  test "llm_provider and llm_model are both optional together" do
    project = Project.new(name: "Demo", repo_folder_path: @repo_dir)
    assert project.valid?
  end

  test "llm_model is required once llm_provider is set" do
    project = Project.new(name: "Demo", repo_folder_path: @repo_dir, llm_provider: "ollama")
    assert_not project.valid?
    assert_includes project.errors[:llm_model], "can't be blank"
  end

  test "llm_provider is required once llm_model is set" do
    project = Project.new(name: "Demo", repo_folder_path: @repo_dir, llm_model: "qwen3.6:latest")
    assert_not project.valid?
    assert_includes project.errors[:llm_provider], "can't be blank"
  end

  test "llm_options includes real openrouter models from RubyLLM's bundled registry" do
    options = Project.llm_options
    openrouter = options.select { |o| o[:provider] == "openrouter" }

    assert_not_empty openrouter
    assert(openrouter.all? { |o| o[:model].present? && o[:label].present? })
  end

  test "llm_options includes ollama models found by a live query against the local server" do
    fake_model = RubyLLM::Model::Info.new(id: "qwen3.6:latest", name: "qwen3.6:latest", provider: "ollama")
    fake_provider = Minitest::Mock.new
    fake_provider.expect(:list_models, [fake_model])

    RubyLLM::Providers::Ollama.stub(:new, fake_provider) do
      options = Project.llm_options
      assert_includes options, { provider: "ollama", model: "qwen3.6:latest", label: fake_model.label }
    end
  end

  test "llm_options omits ollama entries rather than raising when the local server is unreachable" do
    RubyLLM::Providers::Ollama.stub(:new, ->(*) { raise Faraday::ConnectionFailed, "connection refused" }) do
      options = Project.llm_options
      assert(options.none? { |o| o[:provider] == "ollama" })
    end
  end
end
