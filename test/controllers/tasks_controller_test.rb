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
    assert_select "turbo-cable-stream-source", count: 1
  end

  test "unblock clears blocked_reason and redirects back to the task" do
    task = Task.create!(project: @project, title: "Add login", blocked_reason: "human_requested")
    post unblock_project_task_url(@project, task)
    assert_redirected_to project_task_url(@project, task)
    assert_not task.reload.blocked?
  end

  test "update_status manually overrides the task's status" do
    task = Task.create!(project: @project, title: "Add login")
    patch update_status_project_task_url(@project, task), params: { status: "completed" }
    assert_redirected_to project_task_url(@project, task)
    assert task.reload.completed?
  end

  test "update_status rejects an unknown status value" do
    task = Task.create!(project: @project, title: "Add login")
    patch update_status_project_task_url(@project, task), params: { status: "vibes" }
    assert_redirected_to project_task_url(@project, task)
    assert task.reload.pending?
  end

  test "clear_completed deletes only completed tasks, including their worktrees and archives" do
    archive_root = Dir.mktmpdir("archive_root")
    previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = archive_root

    post project_tasks_url(@project), params: { task: { title: "Done task", description: "d" } }
    done_task = @project.tasks.find_by!(title: "Done task")
    post project_tasks_url(@project), params: { task: { title: "Still going", description: "d" } }
    active_task = @project.tasks.find_by!(title: "Still going")
    patch update_status_project_task_url(@project, done_task), params: { status: "completed" }

    delete clear_completed_project_tasks_url(@project)

    assert_redirected_to project_url(@project)
    refute Task.exists?(done_task.id)
    refute Dir.exist?(done_task.worktree_path)
    assert Task.exists?(active_task.id)
    assert Dir.exist?(active_task.worktree_path)
  ensure
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = previous_env
    FileUtils.rm_rf(archive_root) if defined?(archive_root)
  end

  test "clear_completed is a no-op when nothing is completed" do
    task = Task.create!(project: @project, title: "Still going")
    delete clear_completed_project_tasks_url(@project)
    assert_redirected_to project_url(@project)
    assert Task.exists?(task.id)
  end

  test "destroy removes worktree and archive" do
    archive_root = Dir.mktmpdir("archive_root")
    previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = archive_root

    create_url = project_tasks_url(@project)
    post create_url, params: { task: { title: "Remove me", description: "will be destroyed" } }
    task = @project.tasks.sole

    assert Dir.exist?(task.worktree_path)
    assert File.exist?(TaskDocument.doc_path(task))

    delete project_task_url(@project, task)
    assert_redirected_to project_url(@project)
    refute Task.exists?(task.id)
    refute Dir.exist?(task.worktree_path)
  ensure
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = previous_env
    FileUtils.rm_rf(archive_root) if defined?(archive_root)
  end
end
