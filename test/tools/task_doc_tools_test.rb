require "test_helper"

class TaskDocToolsTest < ActiveSupport::TestCase
  def setup
    @archive_root = Dir.mktmpdir("archive_root")
    @previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @archive_root

    @repo_dir = Dir.mktmpdir("task_doc_tools_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @previous_env
    FileUtils.rm_rf(@archive_root)
    FileUtils.rm_rf(@repo_dir)
  end

  test "ReadTaskDocTool returns empty string before anything is written" do
    assert_equal "", ReadTaskDocTool.new(task: @task).execute
  end

  test "WriteTaskDocTool persists content that ReadTaskDocTool then returns" do
    WriteTaskDocTool.new(task: @task).execute(content: "## Plan\n\n- [ ] step one")
    assert_equal "## Plan\n\n- [ ] step one", ReadTaskDocTool.new(task: @task).execute
  end

  test "WriteTaskDocTool writes outside the task's git worktree" do
    WriteTaskDocTool.new(task: @task).execute(content: "persisted")
    assert_not_includes TaskDocument.doc_path(@task), @repo_dir
  end
end
