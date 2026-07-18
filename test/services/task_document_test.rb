require "test_helper"

class TaskDocumentTest < ActiveSupport::TestCase
  def setup
    @archive_root = Dir.mktmpdir("archive_root")
    @previous_env = ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", nil)
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @archive_root

    @repo_dir = Dir.mktmpdir("task_document_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    ENV["ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT"] = @previous_env
    FileUtils.rm_rf(@archive_root)
    FileUtils.rm_rf(@repo_dir)
  end

  test "doc_path is namespaced under the project and task id" do
    expected = File.join(@archive_root, "projects", @task.project_id.to_s, "tasks", "task-#{@task.id}.md")
    assert_equal expected, TaskDocument.doc_path(@task)
  end

  test "read returns an empty string when nothing has been written yet" do
    assert_equal "", TaskDocument.read(@task)
  end

  test "write creates parent directories and persists content" do
    TaskDocument.write(@task, "# Plan\n\nDo the thing.")
    assert_equal "# Plan\n\nDo the thing.", TaskDocument.read(@task)
  end

  test "seed writes the original request verbatim" do
    TaskDocument.seed(@task, "Please add a login page")
    assert_equal "Please add a login page", TaskDocument.read(@task)
  end

  test "delete removes just the doc file" do
    TaskDocument.write(@task, "content")
    TaskDocument.delete(@task)
    assert_equal "", TaskDocument.read(@task)
  end

  test "delete_archive removes the doc and does not raise when nothing exists yet" do
    assert_nothing_raised { TaskDocument.delete_archive(@task) }
  end

  test "the doc survives even if the worktree path is deleted" do
    TaskDocument.write(@task, "persisted plan")
    FileUtils.rm_rf(@repo_dir)
    assert_equal "persisted plan", TaskDocument.read(@task)
  end

  test "append_guidance adds a Human Guidance section" do
    TaskDocument.write(@task, "## Overview\n\nDo the thing.")
    TaskDocument.append_guidance(@task, "use the Playwright MCP server")

    doc = TaskDocument.read(@task)
    assert_includes doc, "## Overview"
    assert_includes doc, "## Human Guidance"
    assert_includes doc, "use the Playwright MCP server"
  end

  test "append_guidance appends under the existing Human Guidance section on repeat" do
    TaskDocument.append_guidance(@task, "first note")
    TaskDocument.append_guidance(@task, "second note")

    doc = TaskDocument.read(@task)
    assert_equal 1, doc.scan("## Human Guidance").size
    assert_includes doc, "first note"
    assert_includes doc, "second note"
  end
end
