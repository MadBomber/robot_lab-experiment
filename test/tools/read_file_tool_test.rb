require "test_helper"

class ReadFileToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("read_file_tool_test")
    File.write(File.join(@dir, "hello.txt"), "hello world")
    @tool = ReadFileTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "reads a file relative to cwd" do
    assert_equal "hello world", @tool.execute(path: "hello.txt")
  end

  test "raises when the file does not exist" do
    error = assert_raises(RobotLab::ToolError) { @tool.execute(path: "missing.txt") }
    assert_match "no such file", error.message
  end

  test "raises when the path escapes cwd" do
    error = assert_raises(RobotLab::ToolError) { @tool.execute(path: "../../etc/passwd") }
    assert_match "escapes the working directory", error.message
  end
end
