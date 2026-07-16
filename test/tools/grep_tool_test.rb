require "test_helper"

class GrepToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("grep_tool_test")
    File.write(File.join(@dir, "a.rb"), "class Foo\nend\n")
    File.write(File.join(@dir, "b.rb"), "class Bar\nend\n")
    @tool = GrepTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "returns file:line:content for each match" do
    result = @tool.execute(pattern: "class Foo")
    assert_equal "a.rb:1:class Foo", result
  end

  test "returns a friendly message when nothing matches" do
    assert_equal "No matches", @tool.execute(pattern: "nonexistent")
  end

  test "scopes matches to a glob filter" do
    result = @tool.execute(pattern: "^class", glob: "a.rb")
    assert_equal "a.rb:1:class Foo", result
  end

  test "raises on an invalid regular expression" do
    error = assert_raises(RobotLab::ToolError) { @tool.execute(pattern: "(unclosed") }
    assert_match "invalid pattern", error.message
  end
end
