require "test_helper"

class GithubIssueServiceTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("github_issue_service_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    @project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "list parses open issues on success" do
    payload = [{ "number" => 5, "title" => "Bug one", "url" => "https://github.com/x/y/issues/5" }].to_json
    Open3.stub(:capture3, ->(*_args, **_kwargs) { [payload, "", Struct.new(:success?).new(true)] }) do
      issues = GithubIssueService.list(@project)
      assert_equal 1, issues.size
      assert_equal 5, issues.first.number
      assert_equal "Bug one", issues.first.title
      assert_equal "https://github.com/x/y/issues/5", issues.first.url
      assert_nil issues.first.body
    end
  end

  test "list returns an empty array when gh fails" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["", "not a git repository", Struct.new(:success?).new(false)] }) do
      assert_equal [], GithubIssueService.list(@project)
    end
  end

  test "list returns an empty array when gh raises" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { raise Errno::ENOENT, "gh" }) do
      assert_equal [], GithubIssueService.list(@project)
    end
  end

  test "find parses a single issue on success" do
    payload = { "number" => 5, "title" => "Bug one", "body" => "Steps to reproduce...",
                "url" => "https://github.com/x/y/issues/5" }.to_json
    Open3.stub(:capture3, ->(*_args, **_kwargs) { [payload, "", Struct.new(:success?).new(true)] }) do
      issue = GithubIssueService.find(@project, 5)
      assert_equal 5, issue.number
      assert_equal "Bug one", issue.title
      assert_equal "Steps to reproduce...", issue.body
    end
  end

  test "find returns nil when gh fails" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["", "no such issue", Struct.new(:success?).new(false)] }) do
      assert_nil GithubIssueService.find(@project, 999)
    end
  end
end
