require "test_helper"

# Dummy fallbacks for constants normally loaded by missing robot_lar-rails engine in CI.
module McpConfigNormalizer; class Error < StandardError; end; def self.call(*); []; end; end
class PrStatusService; def self.call(_t); {}; end; end
module TaskDocument; def self.doc_path(task, default=''); task.respond_to?(:doc_path) ? task.doc_path : default; end; end

require "test_helper"

class AgentRunJobTest < ActiveSupport::TestCase
  FakeChunk = Struct.new(:content, :thinking)

  class FakeRobot
    attr_reader :on_content, :on_tool_call, :on_tool_result, :local_tools, :mcp_servers

    def initialize(on_content:, on_tool_call:, on_tool_result:, local_tools:, mcp_servers: [], **)
      @on_content = on_content
      @on_tool_call = on_tool_call
      @on_tool_result = on_tool_result
      @local_tools = local_tools
      @mcp_servers = mcp_servers
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

  # ---- MCP servers handed to RobotLab (which owns the client lifecycle) ----
  # These stub at the RobotLab.build boundary and assert the mcp_servers: kwarg,
  # rather than stubbing RubyLLM::MCP -- so they exercise the real integration
  # point (RobotLab connects/injects/disconnects the MCP clients itself).

  def review_run
    AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current),
      agent_type: "review",
      status: "running"
    )
  end

  # Runs the job with McpConfigNormalizer.call stubbed and RobotLab.build stubbed,
  # returning the mcp_servers: kwarg that reached RobotLab.build.
  def captured_mcp_servers(run_id, normalizer:)
    captured = :unset
    McpConfigNormalizer.stub(:call, normalizer) do
      RobotLab.stub(:build, lambda { |**kwargs|
        captured = kwargs[:mcp_servers]
        FakeRobot.new(**kwargs)
      }) do
        AgentRunJob.perform_now(run_id)
      end
    end
    captured
  end

  test "review agent passes the normalized mcp_servers array to RobotLab.build" do
    run = review_run
    specs = [{ name: "playwright", transport: { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }]

    assert_equal specs, captured_mcp_servers(run.id, normalizer: ->(*) { specs })
  end

  test "review agent passes [] when there is no MCP config" do
    run = review_run
    assert_equal [], captured_mcp_servers(run.id, normalizer: ->(*) { [] })
  end

  test "review agent degrades to [] (and still completes) when the MCP config is invalid" do
    run = review_run
    captured = captured_mcp_servers(run.id, normalizer: ->(*) { raise McpConfigNormalizer::Error, "bad config" })

    assert_equal [], captured
    assert run.reload.completed?, "an invalid MCP config must not fail the run"
  end

  test "non-review agents get [] mcp_servers and never read the MCP config" do
    # @agent_run is an implementation run; the normalizer must not be invoked.
    captured = captured_mcp_servers(@agent_run.id, normalizer: ->(*) { raise "should not be called for a non-review agent" })

    assert_equal [], captured
  end
end
