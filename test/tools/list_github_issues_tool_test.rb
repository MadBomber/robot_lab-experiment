require "test_helper"

class ListGithubIssuesToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("list_github_issues_tool_test")
    @tool = ListGithubIssuesTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "returns gh's output on success" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ['[{"number":1,"title":"Bug"}]', "", Struct.new(:success?).new(true)] }) do
      assert_equal '[{"number":1,"title":"Bug"}]', @tool.execute
    end
  end

  test "returns a friendly message when there are no open issues" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["", "", Struct.new(:success?).new(true)] }) do
      assert_equal "No open issues.", @tool.execute
    end
  end

  test "raises when gh fails" do
    Open3.stub(:capture3, ->(*_args, **_kwargs) { ["", "not a git repository", Struct.new(:success?).new(false)] }) do
      error = assert_raises(RobotLab::ToolError) { @tool.execute }
      assert_match "gh issue list failed", error.message
    end
  end
end
