require "test_helper"

class AuditTasksControllerTest < ActionDispatch::IntegrationTest
  def setup
    @repo_dir = Dir.mktmpdir("audit_tasks_controller_test_repo")
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

  test "create makes an audit task with its own worktree and a seeded task doc" do
    archive_root = Dir.mktmpdir("archive_root")
    previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = archive_root

    post project_audit_tasks_url(@project)

    task = @project.tasks.sole
    assert_redirected_to project_task_url(@project, task)
    assert task.audit?
    assert Dir.exist?(task.worktree_path)
    assert_includes TaskDocument.read(task), "Self-audit"
  ensure
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = previous_env
    FileUtils.rm_rf(archive_root)
  end

  test "redirects to the project with an alert when the worktree cannot be created" do
    WorktreeService.stub(:new, ->(_task) { raise WorktreeService::Error, "boom" }) do
      post project_audit_tasks_url(@project)
    end

    assert_redirected_to project_url(@project)
    assert_equal 0, @project.tasks.count
  end
end
