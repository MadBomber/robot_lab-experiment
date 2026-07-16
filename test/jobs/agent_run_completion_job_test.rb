require "test_helper"

class AgentRunCompletionJobTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("agent_run_completion_job_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "delegates to AgentRunCompletionHandler for the given run" do
    conversation = Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    run = AgentRun.create!(task: @task, conversation:, agent_type: "implementation", status: "completed")

    assert_enqueued_with(job: AgentRunJob) do
      AgentRunCompletionJob.perform_now(run.id)
    end

    assert_equal "review", @task.agent_runs.order(:id).last.agent_type
  end
end
