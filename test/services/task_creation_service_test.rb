require "test_helper"

class TaskCreationServiceTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("task_creation_service_repo")
    Dir.chdir(@repo_dir) do
      system("git", "init", "--quiet")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "user.name", "Test")
      File.write("README.md", "hello")
      system("git", "add", "README.md")
      system("git", "commit", "--quiet", "-m", "initial commit")
    end
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)

    @archive_root = Dir.mktmpdir("archive_root")
    @previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @archive_root
  end

  def teardown
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @previous_env
    FileUtils.remove_entry(@repo_dir)
    FileUtils.rm_rf("#{@repo_dir}-worktrees")
    FileUtils.rm_rf(@archive_root)
  end

  test "creates a task with a worktree and a seeded task doc" do
    task = TaskCreationService.new(
      @project,
      attributes: { title: "Add login", description: "Please add a login page" },
      original_request: "Please add a login page"
    ).call

    assert Task.exists?(task.id)
    assert Dir.exist?(task.worktree_path)
    assert_equal "Please add a login page", TaskDocument.read(task)
  end

  test "raises Error and leaves no Task row when the title is invalid" do
    assert_no_difference "Task.count" do
      assert_raises(TaskCreationService::Error) do
        TaskCreationService.new(@project, attributes: { title: "" }, original_request: "x").call
      end
    end
  end

  test "raises Error and leaves no Task row when the worktree cannot be created" do
    WorktreeService.stub(:new, ->(_task) { raise WorktreeService::Error, "boom" }) do
      assert_no_difference "Task.count" do
        assert_raises(TaskCreationService::Error) do
          TaskCreationService.new(
            @project,
            attributes: { title: "Add login" },
            original_request: "Add login"
          ).call
        end
      end
    end
  end

  # The bug in #44: TaskDocument.seed failing after the Task row and worktree
  # already exist must not leave either behind.
  test "raises Error and cleans up the task row and worktree when seeding the doc fails" do
    TaskDocument.stub(:seed, ->(*) { raise Errno::ENOSPC, "no space left" }) do
      assert_no_difference "Task.count" do
        assert_raises(TaskCreationService::Error) do
          TaskCreationService.new(
            @project,
            attributes: { title: "Add login" },
            original_request: "Add login"
          ).call
        end
      end
    end

    assert_nil @project.tasks.find_by(title: "Add login")
    assert_empty Dir.glob("#{@repo_dir}-worktrees/task-*")
  end
end
