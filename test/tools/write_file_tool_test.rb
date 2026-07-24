require "test_helper"

class WriteFileToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("write_file_tool_test")
    @tool = WriteFileTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "writes a new file, creating parent directories" do
    @tool.execute(path: "nested/dir/file.txt", content: "hi")
    assert_equal "hi", File.read(File.join(@dir, "nested/dir/file.txt"))
  end

  test "overwrites an existing file" do
    File.write(File.join(@dir, "a.txt"), "old")
    @tool.execute(path: "a.txt", content: "new")
    assert_equal "new", File.read(File.join(@dir, "a.txt"))
  end

  test "raises when the path escapes cwd" do
    assert_raises(RobotLab::ToolError) { @tool.execute(path: "../outside.txt", content: "x") }
  end

  test "raises when the path escapes cwd through a symlink" do
    outside = Dir.mktmpdir("write_file_tool_outside")
    begin
      File.symlink(outside, File.join(@dir, "escape"))
      assert_raises(RobotLab::ToolError) { @tool.execute(path: "escape/pwned.txt", content: "x") }
      refute File.exist?(File.join(outside, "pwned.txt"))
    ensure
      FileUtils.remove_entry(outside)
    end
  end
end
