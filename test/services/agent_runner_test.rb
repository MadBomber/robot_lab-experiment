require "test_helper"

class AgentRunnerTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("agent_runner_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "creates a running AgentRun with a stamped conversation and enqueues the job" do
    assert_enqueued_with(job: AgentRunJob) do
      run = AgentRunner.start_agent_run(@task, :planning)

      assert run.running?
      assert_equal "planning", run.agent_type
      assert_equal "ollama", run.conversation.provider
      assert_equal "qwen3.6:latest", run.conversation.model
    end
  end

  test "increments the task's workflow_run_count on every start" do
    assert_difference -> { @task.reload.workflow_run_count }, 1 do
      AgentRunner.start_agent_run(@task, :planning)
    end
  end

  test "flips a pending task to in_progress on first activity" do
    assert @task.pending?
    AgentRunner.start_agent_run(@task, :planning)
    assert @task.reload.in_progress?
  end

  test "raises AlreadyRunningError when a run is already in flight for the task" do
    AgentRunner.start_agent_run(@task, :planning)

    assert_raises(AgentRunner::AlreadyRunningError) do
      AgentRunner.start_agent_run(@task, :implementation)
    end
  end

  test "accepts an explicit provider and model override" do
    run = AgentRunner.start_agent_run(@task, :implementation, provider: "openai", model: "gpt-5")
    assert_equal "openai", run.conversation.provider
    assert_equal "gpt-5", run.conversation.model
  end
end
