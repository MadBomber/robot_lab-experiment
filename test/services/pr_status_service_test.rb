require "test_helper"
require "open3"

class PrStatusServiceTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("pr_status_service_test_repo")
    Dir.chdir(@repo_dir) do
      system("git", "init", "--quiet")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "user.name", "Test")
    end

    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
  end

  def teardown
    FileUtils.rm_rf(@repo_dir)
  end

  private

  def build_task(**attrs)
    defaults = { project: @project, title: "Test Task" }
    Task.create!(defaults.merge(attrs))
  end

  test "returns 'No branch yet.' when no branch_name on task" do
    task = build_task(branch_name: nil)

    result = PrStatusService.call(task)

    assert_equal "No branch yet.", result
  end

  test "happy path parses successful gh pr view JSON output" do
    task = build_task(branch_name: "task/42-my-task")

    payload = { "url" => "https://github.com/example/repo/pull/42", "state" => "OPEN" }.to_json
    Open3.stub(:capture3, lambda do |*_args, **_kwargs|
      [payload, "", Struct.new(:success?).new(true)]
    end) do
      result = PrStatusService.call(task)

      assert_equal "PR already exists: https://github.com/example/repo/pull/42 (state: OPEN).", result
    end
  end

  test "happy path parses closed PR state" do
    task = build_task(branch_name: "task/10-closed-pr")

    payload = { "url" => "https://github.com/example/repo/pull/10", "state" => "CLOSED" }.to_json
    Open3.stub(:capture3, lambda do |*_args, **_kwargs|
      [payload, "", Struct.new(:success?).new(true)]
    end) do
      result = PrStatusService.call(task)

      assert_equal "PR already exists: https://github.com/example/repo/pull/10 (state: CLOSED).", result
    end
  end

  test "returns fallback when gh pr view returns failure exit status" do
    task = build_task(branch_name: "task/42-my-task")

    Open3.stub(:capture3, lambda do |*_args, **_kwargs|
      ["", "no pull request found for branch", Struct.new(:success?).new(false)]
    end) do
      result = PrStatusService.call(task)

      assert_equal "No pull request open yet for branch task/42-my-task.", result
    end
  end

  test "returns fallback when gh raises Errno::ENOENT (not installed)" do
    task = build_task(branch_name: "task/42-my-task")

    Open3.stub(:capture3, lambda do |*_args, **_kwargs|
      raise Errno::ENOENT, "gh"
    end) do
      result = PrStatusService.call(task)

      assert_equal "No pull request open yet for branch task/42-my-task.", result
    end
  end

  test "returns fallback when gh returns success but malformed JSON" do
    task = build_task(branch_name: "task/42-my-task")

    Open3.stub(:capture3, lambda do |*_args, **_kwargs|
      ["not json at all", "", Struct.new(:success?).new(true)]
    end) do
      result = PrStatusService.call(task)

      assert_equal "No pull request open yet for branch task/42-my-task.", result
    end
  end
end
