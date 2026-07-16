require "test_helper"

class EditFileToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("edit_file_tool_test")
    @tool = EditFileTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "replaces a unique occurrence" do
    File.write(File.join(@dir, "a.rb"), "def foo\n  1\nend\n")
    @tool.execute(path: "a.rb", old_string: "1", new_string: "2")
    assert_equal "def foo\n  2\nend\n", File.read(File.join(@dir, "a.rb"))
  end

  test "raises when old_string is not found" do
    File.write(File.join(@dir, "a.rb"), "content")
    error = assert_raises(RobotLab::ToolError) { @tool.execute(path: "a.rb", old_string: "missing", new_string: "x") }
    assert_match "not found", error.message
  end

  test "raises when old_string is not unique and replace_all is false" do
    File.write(File.join(@dir, "a.rb"), "a\na\n")
    error = assert_raises(RobotLab::ToolError) { @tool.execute(path: "a.rb", old_string: "a", new_string: "b") }
    assert_match "not unique", error.message
  end

  test "replace_all replaces every occurrence" do
    File.write(File.join(@dir, "a.rb"), "a\na\n")
    @tool.execute(path: "a.rb", old_string: "a", new_string: "b", replace_all: true)
    assert_equal "b\nb\n", File.read(File.join(@dir, "a.rb"))
  end

  test "treats backslashes in new_string as literal text, not backreferences" do
    File.write(File.join(@dir, "a.rb"), "target")
    @tool.execute(path: "a.rb", old_string: "target", new_string: 'a\1b\0c')
    assert_equal 'a\1b\0c', File.read(File.join(@dir, "a.rb"))
  end
end
