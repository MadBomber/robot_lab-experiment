require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("project_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "valid with a real git repo path" do
    project = Project.new(name: "Demo", repo_folder_path: @repo_dir)
    assert project.valid?
  end

  test "invalid when repo_folder_path is not a git repo" do
    non_repo = Dir.mktmpdir("not_a_repo")
    project = Project.new(name: "Demo", repo_folder_path: non_repo)

    assert_not project.valid?
    assert_includes project.errors[:repo_folder_path], "is not a git repository"
  ensure
    FileUtils.remove_entry(non_repo)
  end

  test "invalid without a name" do
    project = Project.new(repo_folder_path: @repo_dir)
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "repo_folder_path must be unique" do
    Project.create!(name: "First", repo_folder_path: @repo_dir)
    dup = Project.new(name: "Second", repo_folder_path: @repo_dir)

    assert_not dup.valid?
    assert_includes dup.errors[:repo_folder_path], "has already been taken"
  end

  test "effective_cwd is repo_folder_path when no subproject_path" do
    project = Project.new(repo_folder_path: @repo_dir)
    assert_equal @repo_dir, project.effective_cwd
  end

  test "effective_cwd appends subproject_path when present" do
    project = Project.new(repo_folder_path: @repo_dir, subproject_path: "packages/app")
    assert_equal File.join(@repo_dir, "packages/app"), project.effective_cwd
  end
end
