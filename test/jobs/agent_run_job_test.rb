require "test_helper"

class AgentRunJobTest < ActiveSupport::TestCase
  FakeChunk = Struct.new(:content, :thinking)

  class FakeRobot
    attr_reader :on_content, :on_tool_call, :on_tool_result, :local_tools, :mcp, :ran_message, :run_options

    def initialize(on_content:, on_tool_call:, on_tool_result:, local_tools:, mcp: [], **)
      @on_content = on_content
      @on_tool_call = on_tool_call
      @on_tool_result = on_tool_result
      @local_tools = local_tools
      @mcp = mcp
    end

    def run(message, **options)
      @ran_message = message
      @run_options = options
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

  # Emits the identical tool call/result forever -- the within-run PlateauMonitor
  # must interrupt it (this is the Task 21 PR-agent CI-polling loop, in miniature).
  class LoopingRobot < FakeRobot
    def run(_message, **)
      call = RubyLLM::ToolCall.new(id: "t1", name: "bash", arguments: { command: "gh run view 123" })
      loop do
        @on_tool_call.call(call)
        @on_tool_result.call("still failing")
      end
    end
  end

  # Stands in for a robot on the claude_code provider: no RubyLLM tool
  # callbacks fire; the provider's on_event hook gets Claude Code's stream
  # events instead.
  TOOL_USE_EVENT = {
    "type" => "assistant",
    "message" => { "content" => [{ "type" => "tool_use", "id" => "toolu_1", "name" => "mcp__task__read_task_doc",
                                   "input" => {} }] }
  }.freeze
  TOOL_RESULT_EVENT = {
    "type" => "user",
    "message" => { "content" => [{ "type" => "tool_result", "tool_use_id" => "toolu_1", "content" => "the doc" }] }
  }.freeze

  class FakeClaudeCodeRobot < FakeRobot
    attr_reader :provider_options, :build_kwargs

    def initialize(**kwargs)
      super
      @build_kwargs = kwargs
      @provider_options = { top_p: 0.9 }
    end

    def chat
      self
    end

    def with_provider_options(options)
      @provider_options = options
      self
    end

    def run(message, **options)
      @ran_message = message
      @run_options = options
      on_event = @provider_options.dig(:claude_code, :on_event)
      on_event.call(TOOL_USE_EVENT)
      on_event.call(TOOL_RESULT_EVENT)
      @on_content.call(FakeChunk.new("Planned.", nil))
      "final reply"
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

  test "a run looping on the identical tool call is plateaued and blocks the task" do
    RobotLab.stub(:build, ->(**kwargs) { LoopingRobot.new(**kwargs) }) do
      assert_enqueued_with(job: AgentRunCompletionJob) do
        AgentRunJob.perform_now(@agent_run.id)
      end
    end

    assert_equal "blocked", @agent_run.reload.status
    assert_equal "no_progress", @task.reload.blocked_reason
    assert_match(/No progress:/, @task.blocked_detail)
    assert_includes @task.blocked_detail, "run ##{@agent_run.id}"
    assert_includes @task.blocked_detail, "(implementation)"
    assert_equal @agent_run.id, @task.blocked_run_id
  end

  test "a run flagged cancel_requested stops cooperatively and is marked cancelled" do
    @agent_run.update!(cancel_requested: true)

    RobotLab.stub(:build, ->(**kwargs) { FakeRobot.new(**kwargs) }) do
      AgentRunJob.perform_now(@agent_run.id)
    end

    assert_equal "cancelled", @agent_run.reload.status
  end

  test "pending guidance is injected into the run's kickoff message and then cleared" do
    @task.update!(pending_guidance: "use the Playwright MCP server, not Selenium")

    robot = nil
    RobotLab.stub(:build, ->(**kwargs) { robot = FakeRobot.new(**kwargs) }) do
      AgentRunJob.perform_now(@agent_run.id)
    end

    assert_match "use the Playwright MCP server", robot.ran_message
    assert_nil @task.reload.pending_guidance
  end

  test "without pending guidance the kickoff message is just Begin." do
    robot = nil
    RobotLab.stub(:build, ->(**kwargs) { robot = FakeRobot.new(**kwargs) }) do
      AgentRunJob.perform_now(@agent_run.id)
    end

    assert_equal "Begin.", robot.ran_message
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

  test "gives the planning agent read/search tools plus the planning completion tool" do
    planning_run = start_run("planning")

    captured = nil
    RobotLab.stub(:build, lambda { |**kwargs|
      captured = kwargs[:local_tools]
      FakeRobot.new(**kwargs)
    }) do
      AgentRunJob.perform_now(planning_run.id)
    end

    assert(captured.any?(MarkPlanningCompleteTool))
    assert(captured.any?(ReadFileTool))
    assert_empty captured.grep(BashTool), "planning must not get a shell"
  end

  test "gives the pr agent bash plus the pr completion tool" do
    pr_run = start_run("pr")

    captured = nil
    RobotLab.stub(:build, lambda { |**kwargs|
      captured = kwargs[:local_tools]
      FakeRobot.new(**kwargs)
    }) do
      AgentRunJob.perform_now(pr_run.id)
    end

    assert(captured.any?(MarkPrCompleteTool))
    assert(captured.any?(BashTool))
  end

  test "gives the review agent the workflow completion tools but not the planning one" do
    review_run = start_run("review")

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
    audit_run = start_run("audit")

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
  # These stub at the RobotLab.build boundary and assert the mcp: kwarg,
  # rather than stubbing RubyLLM::MCP -- so they exercise the real integration
  # point (RobotLab registers/connects/disconnects the MCP servers itself).

  def review_run
    start_run("review")
  end

  # Materializes a running run of the given type. The partial unique index
  # allows only one running run per task, so setup's run is retired first.
  def start_run(agent_type)
    @agent_run.update!(status: "completed")
    AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current),
      agent_type:,
      status: "running"
    )
  end

  # Runs the job with McpConfigNormalizer.call stubbed and RobotLab.build stubbed,
  # returning the mcp: kwarg that reached RobotLab.build.
  def captured_mcp_servers(run_id, normalizer:)
    captured = :unset
    McpConfigNormalizer.stub(:call, normalizer) do
      RobotLab.stub(:build, lambda { |**kwargs|
        captured = kwargs[:mcp]
        FakeRobot.new(**kwargs)
      }) do
        AgentRunJob.perform_now(run_id)
      end
    end
    captured
  end

  test "review agent passes the normalized MCP server array to RobotLab.build as mcp:" do
    run = review_run
    specs = [{ name: "playwright", transport: { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }]

    assert_equal specs, captured_mcp_servers(run.id, normalizer: ->(*) { specs })
  end

  test "the run inherits the build-time tools and MCP servers instead of Robot#run's :none defaults" do
    robot = nil
    RobotLab.stub(:build, ->(**kwargs) { robot = FakeRobot.new(**kwargs) }) do
      AgentRunJob.perform_now(@agent_run.id)
    end

    assert_equal({ tools: :inherit, mcp: :inherit }, robot.run_options)
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

  test "non-review agents get [] mcp and never read the MCP config" do
    # @agent_run is an implementation run; the normalizer must not be invoked.
    captured = captured_mcp_servers(@agent_run.id, normalizer: ->(*) { raise "should not be called for a non-review agent" })

    assert_equal [], captured
  end

  def claude_code_run(agent_type)
    @agent_run.update!(status: "completed")
    AgentRun.create!(
      task: @task,
      conversation: Conversation.create!(task: @task, provider: "claude_code", model: "sonnet", started_at: Time.current),
      agent_type:,
      status: "running"
    )
  end

  def perform_claude_code(run)
    robot = nil
    RobotLab.stub(:build, ->(**kwargs) { robot = FakeClaudeCodeRobot.new(**kwargs) }) do
      AgentRunJob.perform_now(run.id)
    end
    robot
  end

  test "a claude_code run gets no RubyLLM tools or MCP servers, and runs with none selected" do
    robot = perform_claude_code(claude_code_run("planning"))

    assert_equal [], robot.local_tools
    assert_equal [], robot.mcp
    assert_equal({ tools: :none, mcp: :none }, robot.run_options)
    assert_includes robot.build_kwargs[:system_prompt], "mcp__task__read_task_doc"
  end

  test "a claude_code run hands the CLI the task worktree, a long timeout and its stage's tools" do
    run = claude_code_run("planning")
    options = perform_claude_code(run).provider_options

    assert_equal 0.9, options[:top_p], "existing provider options are kept"
    cli = options[:claude_code]
    assert_equal @task.effective_cwd, cli[:cwd]
    assert_equal AgentRunJob::CLAUDE_CODE_TIMEOUT, cli[:timeout]
    assert_nil cli[:permission_mode]

    args = cli[:args]
    assert_equal "Read,Glob,Grep", args[args.index("--tools") + 1]
    assert_equal "Read,Glob,Grep,mcp__task", args[args.index("--allowedTools") + 1]
    assert_includes args, "--strict-mcp-config"
    assert_equal "project,local", args[args.index("--setting-sources") + 1]

    server = JSON.parse(args[args.index("--mcp-config") + 1]).dig("mcpServers", "task")
    assert_equal Rails.root.join("bin/task_mcp").to_s, server["command"]
    assert_equal [run.id.to_s], server["args"]
    assert File.absolute_path?(server.dig("env", "BUNDLE_GEMFILE"))
  end

  test "a claude_code implementation run accepts edits" do
    options = perform_claude_code(claude_code_run("implementation")).provider_options

    assert_equal "acceptEdits", options.dig(:claude_code, :permission_mode)
  end

  test "Claude Code's tool events reach the transcript and the run completes" do
    run = claude_code_run("planning")
    perform_claude_code(run)

    assert run.reload.completed?
    rows = run.conversation.messages.order(:seq)
    assert_equal %w[tool_use tool_result assistant], rows.pluck(:msg_type)
    assert_equal "mcp__task__read_task_doc", rows.first.payload["tool_name"]
    assert_equal "toolu_1", rows.second.payload["tool_use_id"]
  end

  test "a claude_code run flagged cancel_requested is stopped from the event hook" do
    run = claude_code_run("planning")
    run.update!(cancel_requested: true)
    perform_claude_code(run)

    assert_equal "cancelled", run.reload.status
  end
end
