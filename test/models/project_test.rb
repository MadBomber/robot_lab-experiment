require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  def setup
    # Bare init only -- validation just looks for a .git entry. The two
    # worktree tests add the commit scaffold themselves (`git worktree add`
    # needs a HEAD); the other tests shouldn't pay for it.
    @repo_dir = init_git_repo("project_test_repo")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir, true)
  end

  test "valid with a real git repo path" do
    project = Project.new(name: "Demo", repo_folder_path: @repo_dir)
    assert project.valid?
  end

  test "valid with a git worktree path" do
    commit_git_scaffold(@repo_dir)
    worktree_dir = Dir.mktmpdir("project_test_worktree")
    git! @repo_dir, "worktree", "add", "--quiet", worktree_dir

    project = Project.new(name: "Worktree Demo", repo_folder_path: worktree_dir)
    assert project.valid?, project.errors.full_messages
  ensure
    if worktree_dir
      git! @repo_dir, "worktree", "remove", "--force", worktree_dir
      FileUtils.rm_rf(worktree_dir)
    end
  end

  test "invalid when the path is a task worktree inside a managed container" do
    commit_git_scaffold(@repo_dir)
    container = "#{@repo_dir}-worktrees"
    worktree_dir = File.join(container, "task-99")
    git! @repo_dir, "worktree", "add", "--quiet", worktree_dir

    project = Project.new(name: "Hijack", repo_folder_path: worktree_dir)
    assert_not project.valid?
    assert_includes project.errors[:repo_folder_path], "is a task worktree managed by another project"
  ensure
    FileUtils.rm_rf(container)
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

  test "llm_options lists LM Studio, then apfel models from live queries, then the rest" do
    lms_model = RubyLLM::Model.new(id: "openai/gpt-oss-20b", name: "GPT-OSS 20B", provider: "lms")
    apfel_model = RubyLLM::Model.new(id: "apple-foundationmodel", name: "Apple Foundation Model", provider: "apfel")

    with_local_servers(lms: [lms_model], apfel: [apfel_model]) do
      options = Project.llm_options

      lms_option = { provider: "lms", model: "openai/gpt-oss-20b", label: lms_model.label }
      apfel_option = { provider: "apfel", model: "apple-foundationmodel", label: apfel_model.label }
      assert_equal [lms_option, apfel_option], options.first(2)
      assert_equal "claude_code", options.third[:provider]
    end
  end

  test "llm_options omits a local server's entries rather than raising when it is unreachable" do
    apfel_model = RubyLLM::Model.new(id: "apple-foundationmodel", name: "Apple Foundation Model", provider: "apfel")

    with_local_servers(lms: :down, apfel: [apfel_model]) do
      options = Project.llm_options

      assert(options.none? { |o| o[:provider] == "lms" })
      assert(options.any? { |o| o[:provider] == "apfel" })
    end
  end

  test "local_probe_config fails fast without touching the app's RubyLLM config" do
    config = Project.local_probe_config

    assert_equal 0, config.max_retries
    assert_equal Project::LOCAL_PROBE_TIMEOUT, config.request_timeout
    assert_not_same RubyLLM.config, config
    assert_operator RubyLLM.config.max_retries, :>, 0
  end

  test "a local server that refuses connections costs no retry delay" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close # nothing listens here now, so connections are refused
    original = RubyLLM.config.lms_api_base
    RubyLLM.config.lms_api_base = "http://127.0.0.1:#{port}/v1"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_empty Project.send(:local_options, "lms")
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  ensure
    RubyLLM.config.lms_api_base = original
  end

  test "llm_options offers no ollama entries" do
    with_local_servers(lms: :down, apfel: :down) do
      assert(Project.llm_options.none? { |o| o[:provider] == "ollama" })
    end
  end

  test "llm_options leaves out local models that cannot drive a tool-calling agent" do
    tool_model = RubyLLM::Model.new(id: "qwen/qwen3.8-27b", name: "Qwen", provider: "lms",
                                    capabilities: %w[streaming function_calling])
    chat_only = RubyLLM::Model.new(id: "kev-0.8b", name: "Kev", provider: "lms", capabilities: %w[streaming])
    embedding = RubyLLM::Model.new(id: "text-embedding-nomic", name: "Nomic", provider: "lms",
                                   modalities: { input: %w[text], output: %w[embeddings] })

    with_local_servers(lms: [tool_model, chat_only, embedding], apfel: :down) do
      lms_ids = Project.llm_options.select { |o| o[:provider] == "lms" }.pluck(:model)

      assert_equal ["qwen/qwen3.8-27b"], lms_ids
    end
  end

  test "llm_options offers Claude Code's model aliases after the local servers and before openrouter" do
    with_local_servers(lms: :down, apfel: :down) do
      options = Project.llm_options
      claude = options.select { |o| o[:provider] == "claude_code" }

      assert_equal %w[default opus sonnet haiku], claude.pluck(:model)
      assert_equal "Claude Code - sonnet", claude.third[:label]
      assert_equal "claude_code", options.first[:provider]
      assert_equal "openrouter", options[claude.size][:provider]
    end
  end

  test "claude_code_options is empty when the provider is not registered" do
    RubyLLM::Provider.stub(:providers, {}) do
      assert_equal [], Project.send(:claude_code_options)
    end
  end

  test "pipeline_capable? accepts a chat model that reports no capabilities" do
    apfel_model = RubyLLM::Model.new(id: "apple-foundationmodel", name: "Apple", provider: "apfel")

    assert Project.send(:pipeline_capable?, apfel_model)
  end

  test "local_options is empty for a provider RubyLLM does not know" do
    assert_equal [], Project.send(:local_options, "no_such_provider")
  end

  private

  # Stubs each local provider's constructor: an Array is the models its
  # server reports, :down makes the query fail the way a refused connection does.
  def with_local_servers(lms:, apfel:, &)
    stub_provider(RubyLLM::Providers::LMS, lms) do
      stub_provider(RubyLLM::Providers::Apfel, apfel, &)
    end
  end

  def stub_provider(klass, models, &)
    fake = if models == :down
             ->(*) { raise Faraday::ConnectionFailed, "connection refused" }
           else
             provider = Minitest::Mock.new
             provider.expect(:list_models, models)
             provider
           end
    klass.stub(:new, fake, &)
  end
end
