require "test_helper"

class BashToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("bash_tool_test")
    @tool = BashTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "runs a command in the working directory" do
    File.write(File.join(@dir, "marker.txt"), "")
    output = @tool.execute(command: "ls")
    assert_includes output, "marker.txt"
  end

  test "reports a non-zero exit status" do
    output = @tool.execute(command: "exit 3")
    assert_match(/Error \(exit 3\)/, output)
  end

  test "captures combined stdout and stderr" do
    output = @tool.execute(command: "echo out; echo err 1>&2")
    assert_includes output, "out"
    assert_includes output, "err"
  end

  test "kills a command that exceeds the timeout" do
    output = @tool.execute(command: "sleep 5", timeout: 1)
    assert_includes output, "killed"
  end
end
