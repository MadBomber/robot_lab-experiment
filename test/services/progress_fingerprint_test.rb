require "test_helper"

class ProgressFingerprintTest < ActiveSupport::TestCase
  def setup
    @archive_root = Dir.mktmpdir("fingerprint_test_archive")
    @previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @archive_root

    @repo_dir = Dir.mktmpdir("fingerprint_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project: @project, title: "Do the thing")
  end

  def teardown
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @previous_env
    FileUtils.remove_entry(@archive_root)
    FileUtils.remove_entry(@repo_dir)
  end

  test "identical task state yields an identical fingerprint" do
    TaskDocument.write(@task, "## To-Do List\n- [x] a\n- [ ] b\n")
    assert_equal ProgressFingerprint.for(@task), ProgressFingerprint.for(@task)
  end

  test "checking off a to-do item changes the fingerprint" do
    TaskDocument.write(@task, "## To-Do List\n- [ ] a\n- [ ] b\n")
    before = ProgressFingerprint.for(@task)

    TaskDocument.write(@task, "## To-Do List\n- [x] a\n- [ ] b\n")
    assert_not_equal before, ProgressFingerprint.for(@task)
  end

  test "new review findings change the fingerprint" do
    TaskDocument.write(@task, "## Review Findings\nNEEDS_WORK: fix the thing\n")
    before = ProgressFingerprint.for(@task)

    TaskDocument.write(@task, "## Review Findings\nNEEDS_WORK: fix a different thing\n")
    assert_not_equal before, ProgressFingerprint.for(@task)
  end

  test "does not raise when the task has no worktree yet" do
    assert_nothing_raised { ProgressFingerprint.for(@task) }
  end
end
