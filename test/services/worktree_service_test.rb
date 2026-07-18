require "test_helper"
require "open3"

class WorktreeServiceTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("worktree_test_repo")
    Dir.chdir(@repo_dir) do
      system("git", "init", "--quiet")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "user.name", "Test")
      File.write("README.md", "hello")
      system("git", "add", "README.md")
      system("git", "commit", "--quiet", "-m", "initial commit")
    end

    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project: @project, title: "Add a Login Page!")
  end

  def teardown
    FileUtils.rm_rf(@repo_dir)
    FileUtils.rm_rf("#{@repo_dir}-worktrees")
  end

  test "create adds a sibling worktree on a sanitized branch name" do
    path = WorktreeService.new(@task).create
    @task.reload

    assert_equal "#{@repo_dir}-worktrees/task-#{@task.id}", path
    assert_equal path, @task.worktree_path
    assert_equal "task/#{@task.id}-add-a-login-page", @task.branch_name
    assert Dir.exist?(path)
    assert File.exist?(File.join(path, "README.md"))
  end

  test "create raises when the worktree/branch already exist" do
    WorktreeService.new(@task).create

    assert_raises(WorktreeService::Error) do
      WorktreeService.new(@task).create
    end
  end

  test "remove tears down the worktree directory and branch" do
    service = WorktreeService.new(@task)
    path = service.create

    service.remove

    assert_not Dir.exist?(path)
    branches, _status = Open3.capture2("git", "branch", chdir: @repo_dir)
    assert_no_match(/#{Regexp.escape(@task.branch_name)}/, branches)
  end

  test "remove raises when the worktree removal fails and the directory remains" do
    service = WorktreeService.new(@task)
    path = service.create

    # Simulate git failing while the worktree dir is still present on disk.
    failure = ["", "fatal: could not remove", Struct.new(:success?).new(false)]
    Open3.stub(:capture3, ->(*_args, **_kwargs) { failure }) do
      assert_raises(WorktreeService::Error) { service.remove }
    end

    assert Dir.exist?(path), "the still-present worktree should not be reported as removed"
  end

  test "remove tolerates git errors when the worktree directory is already gone" do
    service = WorktreeService.new(@task)
    path = service.create
    FileUtils.rm_rf(path)

    # git errors because the worktree is missing, but there's nothing left to
    # clean up, so remove must treat it as a benign no-op rather than raise.
    failure = ["", "fatal: is not a working tree", Struct.new(:success?).new(false)]
    Open3.stub(:capture3, ->(*_args, **_kwargs) { failure }) do
      assert_nothing_raised { service.remove }
    end
  end
end
