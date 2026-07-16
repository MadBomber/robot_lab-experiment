require "test_helper"

class TaskCompletionToolsTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("task_completion_tools_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "MarkPlanningCompleteTool sets planning_complete" do
    MarkPlanningCompleteTool.new(task: @task).execute
    assert @task.reload.planning_complete
  end

  test "MarkWorkflowCompleteTool sets workflow_complete" do
    MarkWorkflowCompleteTool.new(task: @task).execute
    assert @task.reload.workflow_complete
  end

  test "MarkWorkflowBlockedTool sets blocked_reason to human_requested" do
    MarkWorkflowBlockedTool.new(task: @task).execute
    assert_equal "human_requested", @task.reload.blocked_reason
    assert @task.blocked?
  end

  test "MarkPrCompleteTool sets pr_agent_complete" do
    MarkPrCompleteTool.new(task: @task).execute
    assert @task.reload.pr_agent_complete
  end
end
