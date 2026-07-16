require "test_helper"

class AgentRunsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @repo_dir = Dir.mktmpdir("agent_runs_controller_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project: @project, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "starts an agent run and redirects back to the task" do
    assert_enqueued_with(job: AgentRunJob) do
      post project_task_agent_runs_url(@project, @task), params: { agent_type: "planning" }
    end
    assert_redirected_to project_task_url(@project, @task)
    assert @task.reload.running_agent_run.present?
  end

  test "redirects with an alert instead of raising when a run is already in flight" do
    AgentRunner.start_agent_run(@task, :planning)

    post project_task_agent_runs_url(@project, @task), params: { agent_type: "implementation" }

    assert_redirected_to project_task_url(@project, @task)
    assert_equal "An agent is already running for this task.", flash[:alert]
  end
end
