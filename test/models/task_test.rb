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

  test "unblock! clears blocked_reason and resets the no-progress streak" do
    task = Task.create!(project: @project, title: "Do the thing", blocked_reason: "no_progress", no_progress_streak: 3)
    task.unblock!
    assert_not task.blocked?
    assert_equal 0, task.no_progress_streak
  end

  test "no_progress is an accepted blocked_reason" do
    task = Task.new(project: @project, title: "Do the thing", blocked_reason: "no_progress")
    assert task.valid?
  end

  test "abandoned is an accepted blocked_reason" do
    task = Task.new(project: @project, title: "Do the thing", blocked_reason: "abandoned")
    assert task.valid?
  end

  test "record_progress! grows the streak on an unchanged fingerprint until plateaued?" do
    task = Task.create!(project: @project, title: "Do the thing")

    # First sighting establishes the fingerprint at streak 0; only repeats count.
    task.record_progress!("same-fp")
    assert_not task.plateaued?

    (Task::NO_PROGRESS_LIMIT - 1).times { task.record_progress!("same-fp") }
    assert_not task.plateaued?, "not yet plateaued one repeat short of the limit"

    task.record_progress!("same-fp")
    assert task.plateaued?
    assert_equal Task::NO_PROGRESS_LIMIT, task.no_progress_streak
  end

  test "record_progress! resets the streak when the fingerprint changes" do
    task = Task.create!(project: @project, title: "Do the thing")
    task.record_progress!("fp-1") # establish
    task.record_progress!("fp-1")
    task.record_progress!("fp-1")
    assert_equal 2, task.no_progress_streak

    task.record_progress!("fp-2")
    assert_equal 0, task.no_progress_streak
    assert_equal "fp-2", task.progress_fingerprint
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

  test "derived_status is pending until a run exists" do
    task = Task.create!(project: @project, title: "Do the thing")
    assert_equal "pending", task.derived_status
  end

  test "derived_status is in_progress once a run exists but planning isn't complete" do
    task = Task.create!(project: @project, title: "Do the thing")
    make_run(task, "planning", status: "running")
    assert_equal "in_progress", task.derived_status
  end

  test "derived_status is in_review after planning completes and before implementation starts" do
    task = Task.create!(project: @project, title: "Do the thing", planning_complete: true)
    make_run(task, "planning", status: "completed")
    assert_equal "in_review", task.derived_status
  end

  test "derived_status returns to in_progress once implementation has started" do
    task = Task.create!(project: @project, title: "Do the thing", planning_complete: true)
    make_run(task, "planning", status: "completed")
    make_run(task, "implementation", status: "running")
    assert_equal "in_progress", task.derived_status
  end

  test "derived_status is completed once the pr agent completes (fix task)" do
    task = Task.create!(project: @project, title: "Do the thing",
                        planning_complete: true, workflow_complete: true, pr_agent_complete: true)
    make_run(task, "pr", status: "completed")
    assert_equal "completed", task.derived_status
  end

  test "derived_status is completed once the audit run completes (audit task)" do
    task = Task.create!(project: @project, title: "Self-audit", task_kind: "audit")
    make_run(task, "audit", status: "completed")
    assert_equal "completed", task.derived_status
  end

  test "derived_status is not completed for a failed audit run" do
    task = Task.create!(project: @project, title: "Self-audit", task_kind: "audit")
    make_run(task, "audit", status: "failed")
    assert_equal "in_progress", task.derived_status
  end

  test "recompute_status! persists derived_status, and is a no-op when already correct" do
    task = Task.create!(project: @project, title: "Do the thing")
    make_run(task, "planning", status: "completed")
    task.update!(planning_complete: true)

    task.recompute_status!
    assert_equal "in_review", task.reload.status

    assert_no_changes -> { task.updated_at } do
      task.recompute_status!
    end
  end

  private

  def make_run(task, agent_type, status:)
    conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    AgentRun.create!(task:, conversation:, agent_type:, status:)
  end
end
