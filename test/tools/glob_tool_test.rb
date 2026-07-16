require "test_helper"

class GlobToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("glob_tool_test")
    FileUtils.mkdir_p(File.join(@dir, "lib"))
    File.write(File.join(@dir, "lib", "a.rb"), "")
    File.write(File.join(@dir, "lib", "b.rb"), "")
    File.write(File.join(@dir, "README.md"), "")
    @tool = GlobTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "finds files matching a recursive glob, returned relative to cwd" do
    result = @tool.execute(pattern: "**/*.rb")
    assert_equal %w[lib/a.rb lib/b.rb], result.split("\n").sort
  end

  test "scopes the search to a given subdirectory" do
    result = @tool.execute(pattern: "*.rb", path: "lib")
    assert_equal %w[lib/a.rb lib/b.rb], result.split("\n").sort
  end

  test "raises when path is not a directory" do
    assert_raises(RobotLab::ToolError) { @tool.execute(pattern: "*", path: "README.md") }
  end
end
