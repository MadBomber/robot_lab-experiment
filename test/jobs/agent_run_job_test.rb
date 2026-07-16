require "test_helper"

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
end
