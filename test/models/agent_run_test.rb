require "test_helper"

class AgentRunTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("agent_run_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
    @conversation = Conversation.create!(
      task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current
    )
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "defaults to pending status" do
    run = AgentRun.create!(task: @task, conversation: @conversation, agent_type: "planning")
    assert run.pending?
  end

  test "only recognizes the four core agent types" do
    run = AgentRun.new(task: @task, conversation: @conversation)
    assert_equal %w[planning implementation review pr], AgentRun.agent_types.keys
    assert_raises(ArgumentError) { run.agent_type = "yolo" }
  end
end
