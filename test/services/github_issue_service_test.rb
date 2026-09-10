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

  test "find parses a single issue with its comments on success" do
    payload = { "number" => 5, "title" => "Bug one", "body" => "Steps to reproduce...",
                "url" => "https://github.com/x/y/issues/5",
                "comments" => [
                  { "author" => { "login" => "reviewer" }, "body" => "Confirmed on main.",
                    "createdAt" => "2026-09-10T17:00:00Z" }
                ] }.to_json
    Open3.stub(:capture3, ->(*_args, **_kwargs) { [payload, "", Struct.new(:success?).new(true)] }) do
      issue = GithubIssueService.find(@project, 5)
      assert_equal 5, issue.number
      assert_equal "Bug one", issue.title
      assert_equal "Steps to reproduce...", issue.body
      assert_equal 1, issue.comments.size
      assert_equal "reviewer", issue.comments.first.author
      assert_equal "Confirmed on main.", issue.comments.first.body
    end
  end

  test "find tolerates a missing comments key" do
    payload = { "number" => 5, "title" => "Bug one", "body" => "Steps...",
                "url" => "https://github.com/x/y/issues/5" }.to_json
    Open3.stub(:capture3, ->(*_args, **_kwargs) { [payload, "", Struct.new(:success?).new(true)] }) do
      assert_equal [], GithubIssueService.find(@project, 5).comments
    end
  end

  test "find returns nil when gh fails" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["", "no such issue", Struct.new(:success?).new(false)] }) do
      assert_nil GithubIssueService.find(@project, 999)
    end
  end

  test "thread_text joins the body and every attributed comment" do
    issue = GithubIssueService::Issue.new(
      number: 5, title: "Bug one", body: "Steps to reproduce...", url: "https://github.com/x/y/issues/5",
      comments: [
        GithubIssueService::Comment.new(author: "reviewer", body: "Confirmed on main.",
                                        created_at: "2026-09-10T17:00:00Z"),
        GithubIssueService::Comment.new(author: "maintainer", body: "Fix in the validator.",
                                        created_at: "2026-09-10T18:00:00Z")
      ]
    )

    text = issue.thread_text

    assert_includes text, "Steps to reproduce..."
    assert_includes text, "--- Comment from reviewer (2026-09-10T17:00:00Z) ---"
    assert_includes text, "Confirmed on main."
    assert_includes text, "--- Comment from maintainer (2026-09-10T18:00:00Z) ---"
    assert_operator text.index("Confirmed on main."), :<, text.index("Fix in the validator.")
  end

  test "thread_text with no comments is just the body" do
    issue = GithubIssueService::Issue.new(number: 5, title: "Bug one", body: "Just the body.",
                                          url: "https://github.com/x/y/issues/5")
    assert_equal "Just the body.", issue.thread_text
  end
end
