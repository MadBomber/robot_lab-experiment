# Base class for tools that read/write files within a task's working directory
# (the git worktree, or the project checkout when no worktree exists). `cwd` is
# bound once at construction time by whoever builds the Robot for an agent run
# -- it is not read dynamically off the robot, since RobotLab::Robot has no
# built-in per-run context accessor for tools to query.
class CodingTool < RobotLab::Tool
  attr_reader :cwd

  def initialize(cwd:, robot: nil)
    super(robot: robot)
    @cwd = File.expand_path(cwd)
  end

  private

  # Resolves a path relative to +cwd+ and refuses anything that escapes it.
  def resolve_path(path)
    full = File.expand_path(path.to_s, cwd)
    return full if full == cwd || full.start_with?("#{cwd}/")

    raise RobotLab::ToolError, "path escapes the working directory: #{path}"
  end
end
