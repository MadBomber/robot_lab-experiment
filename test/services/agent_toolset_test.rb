require "test_helper"

class AgentToolsetTest < ActiveSupport::TestCase
  def setup
    @repo_dir = init_git_repo("agent_toolset_test_repo")
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir, true)
  end

  test "ruby_llm_tools keep each stage's existing tool list" do
    expected = {
      "planning" => %w[read_task_doc write_task_doc read_file glob grep mark_planning_complete],
      "implementation" => %w[read_task_doc write_task_doc read_file write_file edit_file glob grep bash],
      "review" => %w[read_task_doc write_task_doc read_file glob grep bash quality_gate
                     mark_workflow_complete mark_workflow_blocked],
      "pr" => %w[read_task_doc write_task_doc bash mark_pr_complete],
      "audit" => %w[read_task_doc write_task_doc read_file glob grep list_github_issues create_github_issue]
    }

    expected.each do |type, names|
      assert_equal names, toolset(type).ruby_llm_tools.map(&:name), type
    end
  end

  test "bridge_tools leave out everything Claude Code has built in" do
    expected = {
      "planning" => %w[read_task_doc write_task_doc mark_planning_complete],
      "implementation" => %w[read_task_doc write_task_doc],
      "review" => %w[read_task_doc write_task_doc quality_gate mark_workflow_complete mark_workflow_blocked],
      "pr" => %w[read_task_doc write_task_doc mark_pr_complete],
      "audit" => %w[read_task_doc write_task_doc list_github_issues create_github_issue]
    }

    expected.each do |type, names|
      assert_equal names, toolset(type).bridge_tools.map(&:name), type
    end
  end

  test "only implementation gets Claude Code's edit tools, and only it runs under acceptEdits" do
    assert_includes toolset("implementation").claude_code_builtins, "Edit"
    assert_equal "acceptEdits", toolset("implementation").claude_code_permission_mode

    %w[planning review pr audit].each do |type|
      assert_empty toolset(type).claude_code_builtins & %w[Edit Write], type
      assert_nil toolset(type).claude_code_permission_mode, type
    end
  end

  test "planning and audit get no shell" do
    %w[planning audit].each { |type| assert_not_includes toolset(type).claude_code_builtins, "Bash" }
  end

  test "allowed tools pre-approve the stage's non-edit built-ins and the task MCP server" do
    assert_equal %w[Read Glob Grep mcp__task], toolset("planning").claude_code_allowed_tools
    assert_equal %w[Read Glob Grep Bash mcp__task], toolset("implementation").claude_code_allowed_tools
    assert_equal %w[Bash mcp__task], toolset("pr").claude_code_allowed_tools
  end

  test "defaults its task, cwd and sandbox level from the run" do
    set = AgentToolset.new(agent_run: AgentRun.new(task: @task, agent_type: "planning"))

    assert_equal @task, set.task
    assert_equal @task.effective_cwd, set.cwd
    assert_equal CodingTool.effective_sandbox_level(agent_type: "planning"), set.sandbox_level
  end

  private

  def toolset(agent_type)
    AgentToolset.new(agent_run: AgentRun.new(task: @task, agent_type:), task: @task, cwd: @repo_dir,
                     sandbox_level: "tight")
  end
end
