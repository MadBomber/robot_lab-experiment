require "test_helper"

class TaskTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("task_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "defaults to pending status and no blocked_reason" do
    task = Task.create!(project: @project, title: "Do the thing")

    assert task.pending?
    assert_not task.blocked?
  end

  test "blocked? is true once blocked_reason is set" do
    task = Task.create!(project: @project, title: "Do the thing", blocked_reason: "max_iterations")
    assert task.blocked?
  end

  test "blocked_reason must be one of the known reasons" do
    task = Task.new(project: @project, title: "Do the thing", blocked_reason: "vibes")
    assert_not task.valid?
    assert_includes task.errors[:blocked_reason], "is not included in the list"
  end

  test "iteration_cap_reached? at and above MAX_WORKFLOW_RUNS" do
    task = Task.new(workflow_run_count: Task::MAX_WORKFLOW_RUNS - 1)
    assert_not task.iteration_cap_reached?

    task.workflow_run_count = Task::MAX_WORKFLOW_RUNS
    assert task.iteration_cap_reached?
  end

  test "running_agent_run finds the single running AgentRun for this task" do
    task = Task.create!(project: @project, title: "Do the thing")
    conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    running = AgentRun.create!(task:, conversation:, agent_type: "implementation", status: "running")
    other_conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    AgentRun.create!(task:, conversation: other_conversation, agent_type: "review", status: "completed")

    assert_equal running, task.running_agent_run
  end

  test "destroying a task cascades through conversations and agent_runs without violating NOT NULL" do
    task = Task.create!(project: @project, title: "Do the thing")
    conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    AgentRun.create!(task:, conversation:, agent_type: "implementation", status: "running")

    assert_nothing_raised { task.destroy! }
    assert_equal 0, Conversation.where(task_id: task.id).count
    assert_equal 0, AgentRun.where(task_id: task.id).count
  end

  test "effective_cwd prefers worktree_path over the project's cwd" do
    task = Task.new(project: @project, worktree_path: "/tmp/worktrees/task-1")
    assert_equal "/tmp/worktrees/task-1", task.effective_cwd

    task.worktree_path = nil
    assert_equal @project.effective_cwd, task.effective_cwd
  end

  test "runnable_agent_types suggests planning first, then implementation, then pr" do
    task = Task.create!(project: @project, title: "Do the thing")
    assert_equal ["planning"], task.runnable_agent_types

    task.update!(planning_complete: true)
    assert_equal ["implementation"], task.runnable_agent_types

    task.update!(workflow_complete: true)
    assert_equal ["pr"], task.runnable_agent_types

    task.update!(pr_agent_complete: true)
    assert_equal [], task.runnable_agent_types
  end

  test "runnable_agent_types is empty while a run is in flight or the task is blocked" do
    task = Task.create!(project: @project, title: "Do the thing", planning_complete: true)
    conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    AgentRun.create!(task:, conversation:, agent_type: "implementation", status: "running")
    assert_equal [], task.runnable_agent_types

    task.agent_runs.update_all(status: "failed")
    task.update!(blocked_reason: "human_requested")
    assert_equal [], task.reload.runnable_agent_types
  end

  test "unblock! clears blocked_reason" do
    task = Task.create!(project: @project, title: "Do the thing", blocked_reason: "human_requested")
    task.unblock!
    assert_not task.blocked?
  end

  test "task_kind defaults to fix" do
    task = Task.create!(project: @project, title: "Do the thing")
    assert task.fix?
  end

  test "runnable_agent_types for an audit task offers audit once, then nothing" do
    task = Task.create!(project: @project, title: "Self-audit", task_kind: "audit")
    assert_equal ["audit"], task.runnable_agent_types

    conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    AgentRun.create!(task:, conversation:, agent_type: "audit", status: "completed")
    assert_equal [], task.runnable_agent_types
  end
end
