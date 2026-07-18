# Base class for tools that read/write files within a task's working directory
# (the git worktree, or the project checkout when no worktree exists). `cwd` is
# bound once at construction time by whoever builds the Robot for an agent run
# -- it is not read dynamically off the robot, since RobotLab::Robot has no
# built-in per-run context accessor for tools to query.
class CodingTool < RobotLab::Tool
  attr_reader :cwd

  def initialize(cwd:, sandbox_level: nil, robot: nil)
    super(robot: robot)
    @cwd = File.expand_path(cwd)
    @sandbox_level_arg = sandbox_level
  end

  # Agent-type overrides so review can read the whole project tree while
  # planning/implementation get loose access to bundled deps.
  class << self
    def agent_type_override(agent_type)
      {
        planning: "loose", implementation: "loose",
        review: "root", pr: "tight", audit: "loose"
      }[agent_type]
    end

    def effective_sandbox_level(agent_type: nil)
      agent_type_override(agent_type) || ENV.fetch("AGENT_SANDBOX_LEVEL", "tight").to_s.downcase
    end

    # Memoized set of bundled gem paths (readable at the loose + root levels).
    def read_roots
      @read_roots ||= begin
        paths = []
        if defined?(Bundler) && Bundler.respond_to?(:load)
          specs = Bundler.load.specs
          paths.concat(specs.map(&:full_gem_path).uniq) if specs
        end
        paths
      end
    end

    # Memoized directories from AGENT_READABLE_ROOT (comma- or newline-delimited).
    def readable_roots
      @readable_roots ||= ENV.fetch("AGENT_READABLE_ROOT", "")
                             .tr(",", "\n")
                             .split("\n")
                             .map(&:strip)
                             .reject(&:empty?)
                             .map { |r| File.expand_path(r) }
    end
  end

  # Write access is always cwd-confined at every sandbox level (alias for
  # backward compatibility with tool files that use resolve_path).
  def resolve_path(path)
    resolve_write_path(path)
  end

  private

  # The effective sandbox level for this tool instance.  Precedence:
  # constructor arg > class-level agent_type override > ENV fallback "tight".
  def sandbox_level(agent_type: nil)
    (@sandbox_level_arg || self.class.effective_sandbox_level(agent_type: agent_type))&.to_s&.downcase
  end

  # ------------------------------------------------------------------ write
  # Resolve a path relative to +cwd+ and refuse anything that escapes it.
  # Used by *write* tools at *every* sandbox level -- no exceptions.
  def resolve_write_path(path)
    resolve_confined(path)
  end

  # ------------------------------------------------------------------ read

  # Router -- delegates to the level-specific resolver.
  def resolve_read_path(path)
    case sandbox_level
    when "loose" then resolve_confined(path, read_roots)
    when "root"  then resolve_confined(path, readable_roots + read_roots)
    when "none"  then File.expand_path(path.to_s, cwd)
    else              resolve_confined(path) # tight + any unknown value
    end
  end

  # cwd is always allowed; otherwise the path must live under one of +extra_roots+
  # (empty for cwd-only confinement, which is every write and the tight read).
  def resolve_confined(path, extra_roots = [])
    full = File.expand_path(path.to_s, cwd)
    return full if ([cwd] + extra_roots).any? { |root| full == root || full.start_with?("#{root}/") }

    raise RobotLab::ToolError, "path escapes the working directory: #{path}"
  end

  # Instance methods delegate to class-level memoized data.
  def read_roots
    self.class.read_roots
  end

  def readable_roots
    self.class.readable_roots
  end
end
