require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  def setup
    @repo_dir = Dir.mktmpdir("tasks_controller_test_repo")
    Dir.chdir(@repo_dir) do
      system("git", "init", "--quiet")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "user.name", "Test")
      File.write("README.md", "hello")
      system("git", "add", "README.md")
      system("git", "commit", "--quiet", "-m", "initial commit")
    end
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
    FileUtils.rm_rf("#{@repo_dir}-worktrees")
  end

  test "create seeds the task doc with the description and creates a worktree" do
    archive_root = Dir.mktmpdir("archive_root")
    previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = archive_root

    post project_tasks_url(@project), params: { task: { title: "Add login", description: "Please add a login page" } }

    task = @project.tasks.sole
    assert_redirected_to project_task_url(@project, task)
    assert_equal "Please add a login page", TaskDocument.read(task)
    assert Dir.exist?(task.worktree_path)
  ensure
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = previous_env
    FileUtils.rm_rf(archive_root)
  end

  test "new pre-fills title and description from a from_issue param" do
    issue = GithubIssueService::Issue.new(number: 5, title: "Fix the thing", body: "Steps to reproduce...",
                                          url: "https://github.com/x/y/issues/5")
    GithubIssueService.stub(:find, ->(*_args) { issue }) do
      get new_project_task_url(@project, from_issue: 5)
    end

    assert_response :success
    assert_select "input#task_title[value=?]", "Fix the thing"
    assert_select "textarea#task_description", text: /Steps to reproduce.../
  end

  test "new renders a blank form when the from_issue lookup fails" do
    GithubIssueService.stub(:find, ->(*_args) {}) do
      get new_project_task_url(@project, from_issue: 999)
    end

    assert_response :success
    assert_select "input#task_title[value=?]", "Fix the thing", count: 0
  end

  test "show renders the task doc and transcript" do
    task = Task.create!(project: @project, title: "Add login")
    get project_task_url(@project, task)
    assert_response :success
  end

  test "unblock clears blocked_reason and redirects back to the task" do
    task = Task.create!(project: @project, title: "Add login", blocked_reason: "human_requested")
    post unblock_project_task_url(@project, task)
    assert_redirected_to project_task_url(@project, task)
    assert_not task.reload.blocked?
  end
end
