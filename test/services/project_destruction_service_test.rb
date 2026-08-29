require "test_helper"

class ProjectDestructionServiceTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("project_destruction_repo")
    Dir.chdir(@repo_dir) do
      system("git", "init", "--quiet")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "user.name", "Test")
      File.write("README.md", "hello")
      system("git", "add", "README.md")
      system("git", "commit", "--quiet", "-m", "initial commit")
    end
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task1 = Task.create!(project: @project, title: "Task one")
    @task2 = Task.create!(project: @project, title: "Task two")
    @archive_root = Dir.mktmpdir("archive_root")
    @previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @archive_root
  end

  def teardown
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @previous_env
    begin
      FileUtils.remove_entry(@repo_dir) if defined?(@repo_dir) && @repo_dir && Dir.exist?(@repo_dir)
    rescue Errno::ENOENT, Errno::EACCES
      # ignore - might be corrupted by tests or race conditions
    end
    begin
      FileUtils.rm_rf(@archive_root) if defined?(@archive_root) && @archive_root && Dir.exist?(@archive_root)
    rescue Errno::ENOENT, Errno::EACCES
      # ignore
    end
    begin
      worktrees_dir = "#{@repo_dir}-worktrees"
      FileUtils.rm_rf(worktrees_dir) if defined?(@repo_dir) && @repo_dir && Dir.exist?(worktrees_dir)
    rescue Errno::ENOENT, Errno::EACCES
      # ignore
    end
  end

  test "destroys task archives after destroying project" do
    TaskDocument.write(@task1, "archived content task-one")
    TaskDocument.write(@task2, "archived content task-two")

    assert File.exist?(TaskDocument.doc_path(@task1))
    assert File.exist?(TaskDocument.doc_path(@task2))

    service = ProjectDestructionService.new(@project)
    service.call

    refute Project.exists?(@project.id)
    refute File.exist?(TaskDocument.doc_path(@task1))
    refute File.exist?(TaskDocument.doc_path(@task2))
  end

  test "destroys all tasks in the database after service call" do
    ProjectDestructionService.new(@project).call
    assert_equal 0, Task.where(project_id: @project.id).count
  end

  test "raises when a task's git removal fails, but the project is still destroyed" do
    # Stub WorktreeService instances to raise during iteration
    worktree_faker = Object.new
    worktree_faker.define_singleton_method(:remove) { raise StandardError, "git worktree failure" }

    WorktreeService.stub(:new, ->(_t) { worktree_faker }) do
      assert_raises(ProjectDestructionService::Error) do
        ProjectDestructionService.new(@project).call
      end
    end

    # The DB destroy already committed before filesystem cleanup ran, so a
    # filesystem failure afterward must not resurrect the project -- that's
    # the whole point of the fix (DB consistency no longer depends on
    # filesystem operations succeeding).
    refute Project.exists?(@project.id)
  end

  test "a filesystem cleanup failure for one task does not block cleanup of the others" do
    TaskDocument.write(@task1, "archived content task-one")
    TaskDocument.write(@task2, "archived content task-two")

    failing_worktree = Object.new
    failing_worktree.define_singleton_method(:remove) { raise StandardError, "git worktree failure" }

    succeeding_worktree = Object.new
    succeeding_worktree.define_singleton_method(:remove) { nil }

    task1_id = @task1.id
    WorktreeService.stub(:new, ->(t) { t.id == task1_id ? failing_worktree : succeeding_worktree }) do
      assert_raises(ProjectDestructionService::Error) do
        ProjectDestructionService.new(@project).call
      end
    end

    refute Project.exists?(@project.id)
    # task1's cleanup failed before it reached the archive delete -- its
    # archive is left behind, but that's the "stray leftover" tradeoff the
    # fix accepts. task2's cleanup wasn't blocked by task1's failure.
    assert File.exist?(TaskDocument.doc_path(@task1))
    refute File.exist?(TaskDocument.doc_path(@task2))
  end

  test "raises without attempting any filesystem cleanup when the DB destroy itself fails" do
    TaskDocument.write(@task1, "archived content task-one")

    @project.stub(:destroy!, -> { raise ActiveRecord::RecordNotDestroyed, "destroy blocked" }) do
      WorktreeService.stub(:new, ->(_t) { raise "WorktreeService should not be called when destroy! fails" }) do
        assert_raises(ProjectDestructionService::Error) do
          ProjectDestructionService.new(@project).call
        end
      end
    end

    # DB destroy failed and rolled back, so nothing on disk should have been touched.
    assert Project.exists?(@project.id)
    assert File.exist?(TaskDocument.doc_path(@task1))
  end
end
