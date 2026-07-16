# Base class for tools bound to a specific Task rather than a cwd -- used for
# reading/writing the task doc (which lives outside any git worktree) and for
# the completion-signal tools in task_completion_tool.rb.
class TaskScopedTool < RobotLab::Tool
  attr_reader :task

  def initialize(task:, robot: nil)
    super(robot: robot)
    @task = task
  end
end
