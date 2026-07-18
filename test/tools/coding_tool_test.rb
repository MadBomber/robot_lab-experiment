require "test_helper"

class CodingToolTest < ActiveSupport::TestCase
  # NOTE: parallelize_threshold not used in this Rails version;
  # memoization is already isolated per-test-class in our test environment.

  def setup
    @dir = Dir.mktmpdir("coding_tool_test")
    File.write(File.join(@dir, "inside.txt"), "inside content")
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  # -- sandbox level: tight (default) --

  test "sandbox_level defaults to tight when no arg" do
    tool = ReadFileTool.new(cwd: @dir)
    assert_equal "tight", tool.send(:sandbox_level)
  end

  test "sandbox_level accepts constructor override" do
    tool = ReadFileTool.new(cwd: @dir, sandbox_level: "loose")
    assert_equal "loose", tool.send(:sandbox_level)
  end

  test "resolve_read_path tight rejects escaping paths" do
    tool = ReadFileTool.new(cwd: @dir, sandbox_level: "tight")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../../etc/passwd") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "resolve_read_path tight allows cwd-relative paths" do
    tool = ReadFileTool.new(cwd: @dir, sandbox_level: "tight")
    assert_equal "inside content", tool.execute(path: "inside.txt")
  end

  # -- sandbox level: loose --

  test "sandbox_level loose via constructor still rejects escaping paths" do
    tool = ReadFileTool.new(cwd: @dir, sandbox_level: "loose")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../../etc/passwd") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "sandbox_level loose allows cwd-relative reads" do
    tool = ReadFileTool.new(cwd: @dir, sandbox_level: "loose")
    assert_equal "inside content", tool.execute(path: "inside.txt")
  end

  test "sandbox_level loose read_roots captures bundler gem paths" do
    skip "no loaded Bundler specs" unless defined?(Bundler) && Bundler.respond_to?(:load) && Bundler.load.specs.any?

    coder = CodingTool.new(cwd: @dir, sandbox_level: "loose")
    roots = coder.send(:read_roots)
    assert_kind_of Array, roots
  end

  # -- sandbox level: root --

  test "sandbox_level root resolves cwd paths" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "root")
    resolved = coder.send(:resolve_read_path, "inside.txt")
    assert_equal File.expand_path("inside.txt", @dir), resolved
  end

  test "sandbox_level root adds AGENT_READABLE_ROOT directories" do
    original = ENV.fetch("AGENT_READABLE_ROOT", nil)
    begin
      temp_dir = Dir.mktmpdir("root_test")
      File.write(File.join(temp_dir, "readable.txt"), "accessible via root")

      # Clear memoization to pick up the new env var.
      CodingTool.instance_variable_set(:@readable_roots, nil)
      ENV["AGENT_READABLE_ROOT"] = temp_dir

      coder = CodingTool.new(cwd: @dir, sandbox_level: "root")
      assert_includes coder.send(:readable_roots), File.expand_path(temp_dir)
    ensure
      original ? ENV["AGENT_READABLE_ROOT"] = original : ENV.delete("AGENT_READABLE_ROOT")
      FileUtils.remove_entry(temp_dir) if temp_dir && Dir.exist?(temp_dir) rescue nil
      CodingTool.instance_variable_set(:@readable_roots, nil)
    end
  end

  # -- sandbox level: none (unrestricted) --

  test "sandbox_level none allows reads outside cwd" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "none")
    expanded = File.expand_path("../../etc/hosts", @dir)
    assert_equal expanded, coder.send(:resolve_read_path, "../../etc/hosts")
  end

  test "sandbox_level none still expands relative to cwd" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "none")
    expanded = File.expand_path("inside.txt", @dir)
    assert_equal expanded, coder.send(:resolve_read_path, "inside.txt")
  end

  # -- write isolation at all levels --

  test "write paths never escape cwd even at loose level" do
    tool = WriteFileTool.new(cwd: @dir, sandbox_level: "loose")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../outside.txt", content: "x") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "write paths never escape cwd even at root level" do
    tool = WriteFileTool.new(cwd: @dir, sandbox_level: "root")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../outside.txt", content: "x") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "write paths never escape cwd even at none level" do
    tool = WriteFileTool.new(cwd: @dir, sandbox_level: "none")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../outside.txt", content: "x") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "write paths never escape cwd even at tight level" do
    tool = WriteFileTool.new(cwd: @dir, sandbox_level: "tight")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../outside.txt", content: "x") }
    assert_match(/escapes the working directory/, error.message)
  end

  # -- write isolation in edit tool --

  test "edit paths never escape cwd even at loose level" do
    File.write(File.join(@dir, "target.txt"), "original") unless File.exist?(File.join(@dir, "target.txt"))
    tool = EditFileTool.new(cwd: @dir, sandbox_level: "loose")
    error = assert_raises(RobotLab::ToolError) { tool.execute(path: "../escape.txt", old_string: "", new_string: "x") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "resolve_path alias delegates to resolve_write_path for backward compat" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "loose")
    resolved = coder.send(:resolve_path, "inside.txt")
    assert_equal File.expand_path("inside.txt", @dir), resolved

    error = assert_raises(RobotLab::ToolError) { coder.send(:resolve_path, "../escape.txt") }
    assert_match(/escapes the working directory/, error.message)
  end

  # -- env var fallback --

  test "effective_sandbox_level from AGENT_SANDBOX_LEVEL" do
    original = ENV.fetch("AGENT_SANDBOX_LEVEL", nil)
    begin
      ENV["AGENT_SANDBOX_LEVEL"] = "loose"
      assert_equal "loose", CodingTool.effective_sandbox_level

      ENV["AGENT_SANDBOX_LEVEL"] = "ROOT"
      assert_equal "root", CodingTool.effective_sandbox_level
    ensure
      original ? ENV["AGENT_SANDBOX_LEVEL"] = original : ENV.delete("AGENT_SANDBOX_LEVEL")
    end
  end

  test "effective_sandbox_level defaults to tight" do
    original = ENV.fetch("AGENT_SANDBOX_LEVEL", nil)
    begin
      ENV.delete("AGENT_SANDBOX_LEVEL")
      assert_equal "tight", CodingTool.effective_sandbox_level
    ensure
      original ? ENV["AGENT_SANDBOX_LEVEL"] = original : ENV.delete("AGENT_SANDBOX_LEVEL")
    end
  end

  # -- agent_type overrides --

  test "agent_type_override returns correct level for each type" do
    assert_equal "loose", CodingTool.agent_type_override(:planning)
    assert_equal "loose", CodingTool.agent_type_override(:implementation)
    assert_equal "root", CodingTool.agent_type_override(:review)
    assert_equal "tight", CodingTool.agent_type_override(:pr)
    assert_equal "loose", CodingTool.agent_type_override(:audit)
  end

  test "effective_sandbox_level uses agent_type override when present" do
    original = ENV.fetch("AGENT_SANDBOX_LEVEL", nil)
    begin
      ENV.delete("AGENT_SANDBOX_LEVEL")
      assert_equal "root", CodingTool.effective_sandbox_level(agent_type: :review)
      assert_equal "loose", CodingTool.effective_sandbox_level(agent_type: :planning)
    ensure
      original ? ENV["AGENT_SANDBOX_LEVEL"] = original : ENV.delete("AGENT_SANDBOX_LEVEL")
    end
  end

  # -- unknown / invalid level falls back to tight --

  test "invalid sandbox_level falls back to tight behavior" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "banana")
    error = assert_raises(RobotLab::ToolError) { coder.send(:resolve_read_path, "../../etc/passwd") }
    assert_match(/escapes the working directory/, error.message)
  end

  test "nil sandbox_level resolves to tight behavior" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: nil)
    error = assert_raises(RobotLab::ToolError) { coder.send(:resolve_read_path, "../../etc/passwd") }
    assert_match(/escapes the working directory/, error.message)
  end

  # -- cwd-relative paths allowed at all levels --

  test "cwd-relative paths work at tight level" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "tight")
    assert_equal File.expand_path("inside.txt", @dir), coder.send(:resolve_read_path, "inside.txt")
  end

  test "cwd-relative paths work at loose level" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "loose")
    assert_equal File.expand_path("inside.txt", @dir), coder.send(:resolve_read_path, "inside.txt")
  end

  test "cwd-relative paths work at root level" do
    coder = CodingTool.new(cwd: @dir, sandbox_level: "root")
    assert_equal File.expand_path("inside.txt", @dir), coder.send(:resolve_read_path, "inside.txt")
  end

  # -- memoization --

  test "read_roots is memoized on the CodingTool class object" do
    coder1 = CodingTool.new(cwd: @dir, sandbox_level: "loose")
    roots1 = coder1.send(:read_roots)
    coder2 = CodingTool.new(cwd: @dir, sandbox_level: "loose")
    roots2 = coder2.send(:read_roots)
    assert_same roots1, roots2, "read_roots should return the same memoized array"
  end

  test "readable_roots is memoized on the CodingTool class object" do
    original = ENV.fetch("AGENT_READABLE_ROOT", nil)
    begin
      ENV["AGENT_READABLE_ROOT"] = ""
      coder1 = CodingTool.new(cwd: @dir, sandbox_level: "root")
      roots1 = coder1.send(:readable_roots)
      coder2 = CodingTool.new(cwd: @dir, sandbox_level: "root")
      roots2 = coder2.send(:readable_roots)
      assert_same roots1, roots2, "readable_roots should return the same memoized array"
    ensure
      original ? ENV["AGENT_READABLE_ROOT"] = original : ENV.delete("AGENT_READABLE_ROOT")
      CodingTool.instance_variable_set(:@readable_roots, nil)
    end
  end

  test "read_roots is independent of sandbox_level (always computes on first call)" do
    coder1 = CodingTool.new(cwd: @dir, sandbox_level: "tight")
    roots1 = coder1.send(:read_roots)
    coder2 = CodingTool.new(cwd: @dir, sandbox_level: "loose")
    roots2 = coder2.send(:read_roots)
    assert_same roots1, roots2, "read_roots should be shared regardless of level"
  end
end
