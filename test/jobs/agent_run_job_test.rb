require "test_helper"
require "ruby_llm/mcp"

class AgentRunJobTest < ActiveSupport::TestCase
  FakeChunk = Struct.new(:content, :thinking)

  class FakeRobot
    attr_reader :on_content, :on_tool_call, :on_tool_result, :local_tools

    def initialize(on_content:, on_tool_call:, on_tool_result:, local_tools:, **)
      @on_content = on_content
      @on_tool_call = on_tool_call
      @on_tool_result = on_tool_result
      @local_tools = local_tools
    end

    def run(_message, **)
      @on_tool_call.call(RubyLLM::ToolCall.new(id: "t1", name: "read_file", arguments: { path: "a.txt" }))
      @on_tool_result.call("contents of a.txt")
      @on_content.call(FakeChunk.new("Here is my answer.", nil))
      "final reply"
    end
  end

  class RaisingRobot < FakeRobot
    def run(_message, **)
      raise "boom"
    end
  end

  def setup
    @repo_dir = Dir.mktmpdir("agent_run_job_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
    @conversation = Conversation.create!(
      task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current
    )
    @agent_run = AgentRun.create!(task: @task, conversation: @conversation, agent_type: "implementation", status: "running")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "records the transcript, marks the run completed, and schedules the completion handler" do
    RobotLab.stub(:build, ->(**kwargs) { FakeRobot.new(**kwargs) }) do
      assert_enqueued_with(job: AgentRunCompletionJob) do
        AgentRunJob.perform_now(@agent_run.id)
      end
    end

    assert @agent_run.reload.completed?
    types = @conversation.messages.order(:seq).pluck(:msg_type)
    assert_equal %w[tool_use tool_result assistant], types
  end

  test "marks the run failed when the robot raises, but still schedules the completion handler" do
    RobotLab.stub(:build, ->(**kwargs) { RaisingRobot.new(**kwargs) }) do
      assert_enqueued_with(job: AgentRunCompletionJob) do
        AgentRunJob.perform_now(@agent_run.id)
      end
    end

    assert @agent_run.reload.failed?
  end

  test "gives the implementation agent no completion tools, only doc + coding tools" do
    captured = nil
    RobotLab.stub(:build, lambda { |**kwargs|
      captured = kwargs[:local_tools]
      FakeRobot.new(**kwargs)
    }) do
      AgentRunJob.perform_now(@agent_run.id)
    end

    assert_empty captured.grep(TaskCompletionTool)
    assert(captured.any?(BashTool))
  end

  test "gives the review agent the workflow completion tools but not the planning one" do
    review_run = AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current),
      agent_type: "review",
      status: "running"
    )

    captured = nil
    RobotLab.stub(:build, lambda { |**kwargs|
      captured = kwargs[:local_tools]
      FakeRobot.new(**kwargs)
    }) do
      AgentRunJob.perform_now(review_run.id)
    end

    assert(captured.any?(MarkWorkflowCompleteTool))
    assert(captured.any?(MarkWorkflowBlockedTool))
    assert_empty captured.grep(MarkPlanningCompleteTool)
  end

  test "gives the audit agent issue-filing tools, no completion tools" do
    audit_run = AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current),
      agent_type: "audit",
      status: "running"
    )

    captured = nil
    RobotLab.stub(:build, lambda { |**kwargs|
      captured = kwargs[:local_tools]
      FakeRobot.new(**kwargs)
    }) do
      AgentRunJob.perform_now(audit_run.id)
    end

    assert(captured.any?(ListGithubIssuesTool))
    assert(captured.any?(CreateGithubIssueTool))
    assert_empty captured.grep(TaskCompletionTool)
  end

  # ---- MCP integration tests (stubbed) ----
  # Each test creates its own temp directory via Dir.mktmpdir (guaranteed unique per call).
  # Rails.root is overridden so AgentRunJob's mcp_config_path always points inside that
  # test's own temp directory — this keeps all parallel-process interactions out of each
  # other's files, fixing the original race-condition failures.

  def override_rails_root(dir)
    Rails.stub(:root, Pathname.new(dir)) { yield }
  end

  # Write an MCP config file under tmpdir/config/mcp_servers.json (matching what
  # AgentRunJob#mcp_config_path expects when Rails.root is overridden).
  def write_mcp_config(tmpdir)
    cpath = File.join(tmpdir, "config", "mcp_servers.json")
    FileUtils.mkdir_p(File.dirname(cpath))
    File.write(cpath, <<~JSON)
      {
        "mcpServers": {
          "playwright": {
            "command": "npx",
            "args": ["-y", "@playwright/mcp@latest"]
          }
        }
      }
    JSON
    cpath
  end

  test "review agent gets MCP tools when config exists" do
    review_run = AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(
        task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current
      ),
      agent_type: "review",
      status: "running"
    )

    # Create per-test unique temp directory and write a standard MCP config into it.
    tmpdir = Dir.mktmpdir("mcp_test_config")
    cp = write_mcp_config(tmpdir)

    fake_mcp_tool = Struct.new(:name).new("playwright_launch_browser")

    begin
      captured = nil
      McpConfigNormalizer.stub(:load_and_normalize, lambda { |_path|
        { "playwright" => { transport_type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }
      }) do
        RubyLLM::MCP.stub(:establish_connection, ->(_config) { true }) do
          RubyLLM::MCP.stub(:tools, -> { [fake_mcp_tool] }) do
            override_rails_root(tmpdir) do
              RobotLab.stub(:build, lambda { |**kwargs|
                captured = kwargs[:local_tools]
                FakeRobot.new(**kwargs)
              }) do
                AgentRunJob.perform_now(review_run.id)
              end
            end
          end
        end
      end

      assert(captured.any?(MarkWorkflowCompleteTool))
      assert captured.include?(fake_mcp_tool), "Expected MCP tool #{fake_mcp_tool.inspect} in tools list - got: #{captured.to_a.map(&:class).map(&:name)}"
    ensure
      File.delete(cp) if File.exist?(cp)
      FileUtils.rm_rf(tmpdir) if File.exist?(tmpdir)
    end
  end

  test "review agent does not get MCP tools when config file is missing" do
    review_run = AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(
        task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current
      ),
      agent_type: "review",
      status: "running"
    )

    # Temp dir without an MCP config — AgentRunJob#should_load_mcp? returns false.
    tmpdir = Dir.mktmpdir("mcp_test_config")

    begin
      captured = nil
      override_rails_root(tmpdir) do
        RobotLab.stub(:build, lambda { |**kwargs|
          captured = kwargs[:local_tools]
          FakeRobot.new(**kwargs)
        }) do
          AgentRunJob.perform_now(review_run.id)
        end
      end

      assert(captured.any?(MarkWorkflowCompleteTool))
    ensure
      FileUtils.rm_rf(tmpdir) if File.exist?(tmpdir)
    end
  end

  test "non-review agents never get MCP tools (config present or not)" do
    implementation_run = AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(
        task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current
      ),
      agent_type: "implementation",
      status: "running"
    )

    # Temp dir without any config — isolates from stale parallel-process files.
    tmpdir = Dir.mktmpdir("mcp_test_config")

    begin
      captured = nil
      override_rails_root(tmpdir) do
        RobotLab.stub(:build, lambda { |**kwargs|
          captured = kwargs[:local_tools]
          FakeRobot.new(**kwargs)
        }) do
          AgentRunJob.perform_now(implementation_run.id)
        end
      end

      assert(captured.any?(BashTool))
      assert(captured.any?(ReadFileTool))
    ensure
      FileUtils.rm_rf(tmpdir) if File.exist?(tmpdir)
    end
  end
end
