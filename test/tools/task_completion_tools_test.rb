require "test_helper"

class TaskCompletionToolsTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("task_completion_tools_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "MarkPlanningCompleteTool sets planning_complete" do
    MarkPlanningCompleteTool.new(task: @task).execute
    assert @task.reload.planning_complete
  end

  test "MarkWorkflowCompleteTool sets workflow_complete" do
    MarkWorkflowCompleteTool.new(task: @task).execute
    assert @task.reload.workflow_complete
  end

  test "MarkWorkflowBlockedTool sets blocked_reason to human_requested" do
    MarkWorkflowBlockedTool.new(task: @task).execute
    assert_equal "human_requested", @task.reload.blocked_reason
    assert @task.blocked?
  end

  test "MarkPrCompleteTool completes when there is genuinely nothing to submit" do
    # Fresh repo: no commits ahead, clean worktree -> nothing to submit.
    assert_match(/marked complete/, MarkPrCompleteTool.new(task: @task).execute)
    assert @task.reload.pr_agent_complete
  end

  test "MarkPrCompleteTool refuses while the worktree has uncommitted changes" do
    File.write(File.join(@repo_dir, "pending.txt"), "not committed")

    tool = MarkPrCompleteTool.new(task: @task)
    assert tool.dirty_worktree?, "expected the new untracked file to make the worktree dirty"
    result = tool.execute

    assert_match(/uncommitted changes/, result)
    refute @task.reload.pr_agent_complete, "must not complete with uncommitted work"
  end

  test "MarkPrCompleteTool completes a committed branch when no remote is configured" do
    tool = MarkPrCompleteTool.new(task: @task)
    tool.stub(:dirty_worktree?, false) do
      tool.stub(:commits_ahead?, true) do
        tool.stub(:remote_configured?, false) do
          assert_match(/marked complete/, tool.execute)
        end
      end
    end
    assert @task.reload.pr_agent_complete
  end

  test "MarkPrCompleteTool refuses a committed branch with a remote but no open PR" do
    @task.update!(branch_name: "task/1-demo")
    tool = MarkPrCompleteTool.new(task: @task)
    tool.stub(:dirty_worktree?, false) do
      tool.stub(:commits_ahead?, true) do
        tool.stub(:remote_configured?, true) do
          tool.stub(:open_pr?, false) do
            assert_match(/no open PR/, tool.execute)
          end
        end
      end
    end
    refute @task.reload.pr_agent_complete, "must not complete without an open PR when a remote exists"
  end

  test "MarkPrCompleteTool completes a committed branch once an open PR exists" do
    @task.update!(branch_name: "task/1-demo")
    tool = MarkPrCompleteTool.new(task: @task)
    tool.stub(:dirty_worktree?, false) do
      tool.stub(:commits_ahead?, true) do
        tool.stub(:remote_configured?, true) do
          tool.stub(:open_pr?, true) do
            assert_match(/marked complete/, tool.execute)
          end
        end
      end
    end
    assert @task.reload.pr_agent_complete
  end
end
