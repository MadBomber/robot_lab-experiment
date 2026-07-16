require "test_helper"

class AgentRunCompletionHandlerTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("completion_handler_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "planning finishing always stops, even if other flags would otherwise chain" do
    task = build_task(workflow_complete: true)
    run = finished_run(task, "planning")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :stopped_after_planning, result.action
    assert_nil result.next_agent_run
    assert_equal 0, task.agent_runs.where.not(id: run.id).count
  end

  test "audit finishing always stops, even if other flags would otherwise chain" do
    task = build_task(workflow_complete: true, task_kind: "audit")
    run = finished_run(task, "audit")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :stopped_after_audit, result.action
    assert_nil result.next_agent_run
    assert_equal 0, task.agent_runs.where.not(id: run.id).count
  end

  test "implementation finishing with no flags chains to review" do
    task = build_task
    run = finished_run(task, "implementation")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :chained_to_review, result.action
    assert_equal "review", result.next_agent_run.agent_type
  end

  test "review finishing with no flags (NEEDS_WORK) chains back to implementation" do
    task = build_task
    run = finished_run(task, "review")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :chained_to_implementation, result.action
    assert_equal "implementation", result.next_agent_run.agent_type
  end

  test "review setting workflow_complete (READY) starts the PR agent" do
    task = build_task(workflow_complete: true)
    run = finished_run(task, "review")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :started_pr, result.action
    assert_equal "pr", result.next_agent_run.agent_type
  end

  test "a finishing PR run with workflow_complete and pr_agent_complete both set is terminal" do
    task = build_task(workflow_complete: true, pr_agent_complete: true)
    run = finished_run(task, "pr")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :already_complete, result.action
    assert_nil result.next_agent_run
  end

  test "review setting blocked_reason (BLOCKED) stops the loop" do
    task = build_task(blocked_reason: "human_requested")
    run = finished_run(task, "review")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :stopped_blocked, result.action
    assert_nil result.next_agent_run
  end

  test "hitting the iteration cap auto-blocks the task instead of chaining" do
    task = build_task(workflow_run_count: Task::MAX_WORKFLOW_RUNS)
    run = finished_run(task, "review")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :blocked_max_iterations, result.action
    assert_nil result.next_agent_run
    assert_equal "max_iterations", task.reload.blocked_reason
  end

  test "workflow_complete is checked before the iteration cap, so a READY review still routes to PR" do
    task = build_task(workflow_complete: true, workflow_run_count: Task::MAX_WORKFLOW_RUNS)
    run = finished_run(task, "review")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :started_pr, result.action
  end

  test "a failed run never chains, regardless of flags" do
    task = build_task(workflow_complete: true)
    run = finished_run(task, "implementation", status: "failed")

    result = AgentRunCompletionHandler.call(run)

    assert_equal :failed_no_chain, result.action
    assert_nil result.next_agent_run
  end

  test "does not start a second run if one is already running for the task" do
    task = build_task
    finished_run(task, "implementation") # this one just finished
    make_run(task, "review", status: "running") # something else is already running

    run = task.agent_runs.find_by(agent_type: "implementation")
    result = AgentRunCompletionHandler.call(run)

    assert_equal :already_running, result.action
    assert_nil result.next_agent_run
  end

  private

  def build_task(**attrs)
    Task.create!(project: @project, title: "Do the thing", **attrs)
  end

  def finished_run(task, agent_type, status: "completed")
    make_run(task, agent_type, status:)
  end

  def make_run(task, agent_type, status:)
    conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    AgentRun.create!(task:, conversation:, agent_type:, status:)
  end
end
