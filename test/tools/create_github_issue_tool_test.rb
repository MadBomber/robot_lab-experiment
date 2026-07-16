require "test_helper"

class CreateGithubIssueToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("create_github_issue_tool_test")
    @tool = CreateGithubIssueTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "returns the created issue URL on success" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["https://github.com/x/y/issues/1\n", "", Struct.new(:success?).new(true)] }) do
      result = @tool.execute(title: "Bug", body: "Something is broken")
      assert_equal "Filed: https://github.com/x/y/issues/1", result
    end
  end

  test "raises when gh fails" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["", "not authenticated", Struct.new(:success?).new(false)] }) do
      error = assert_raises(RobotLab::ToolError) { @tool.execute(title: "Bug", body: "Something is broken") }
      assert_match "gh issue create failed", error.message
    end
  end

  test "refuses to file more than MAX_ISSUES_PER_RUN issues in one run" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["https://github.com/x/y/issues/1\n", "", Struct.new(:success?).new(true)] }) do
      CreateGithubIssueTool::MAX_ISSUES_PER_RUN.times do |n|
        @tool.execute(title: "Bug #{n}", body: "Something is broken")
      end

      error = assert_raises(RobotLab::ToolError) { @tool.execute(title: "One too many", body: "...") }
      assert_match "already filed", error.message
    end
  end
end
