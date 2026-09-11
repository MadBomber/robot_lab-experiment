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

  test "redirects with an alert when agent_type is invalid" do
    post project_task_agent_runs_url(@project, @task), params: { agent_type: "yolo" }

    assert_redirected_to project_task_url(@project, @task)
    assert_equal "Invalid agent type: yolo", flash[:alert]
    assert_not @task.reload.running_agent_run.present?
  end

  test "show orders transcript messages by seq regardless of created_at skew" do
    conversation = Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    run = AgentRun.create!(task: @task, conversation:, agent_type: "implementation", status: "completed")

    first = Message.create!(conversation:, msg_type: :user, seq: 1, uuid: SecureRandom.uuid,
                            created_at: 2.hours.ago, payload: { content: "first" })
    second = Message.create!(conversation:, msg_type: :assistant, seq: 2, uuid: SecureRandom.uuid,
                             created_at: 3.hours.ago, payload: { content: "second" })

    get project_task_agent_run_url(@project, @task, run)

    assert_response :success
    labels = css_select('pre[data-slot="code-block-pre"]').map { |el| el["aria-label"] }
    assert_equal ["Message #{first.id} payload", "Message #{second.id} payload"], labels
  end
end
