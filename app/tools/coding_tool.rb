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
    full = File.expand_path(path.to_s, cwd)
    return full if full == cwd || full.start_with?("#{cwd}/")

    raise RobotLab::ToolError, "path escapes the working directory: #{path}"
  end

  # ------------------------------------------------------------------ read

  # Router -- delegates to the level-specific resolver.
  def resolve_read_path(path)
    level = sandbox_level
    case level
    when "loose" then resolve_read_loose(path)
    when "root"  then resolve_read_root(path)
    when "none"  then resolve_read_unrestricted(path)
    else                resolve_read_tight(path)  # tight + any unknown value
    end
  end

  def resolve_read_unrestricted(path)
    File.expand_path(path.to_s, cwd)
  end

  def resolve_read_tight(path)
    full = File.expand_path(path.to_s, cwd)
    return full if full == cwd || full.start_with?("#{cwd}/")

    raise RobotLab::ToolError, "path escapes the working directory: #{path}"
  end

  def resolve_read_loose(path)
    # Tight check first -- handles everything inside cwd quickly.
    tight = File.expand_path(path.to_s, cwd)
    return tight if tight == cwd || tight.start_with?("#{cwd}/")

    # Fall back to bundler gem paths.
    expanded = File.expand_path(path.to_s, cwd)
    read_roots.each do |root|
      return expanded if expanded == root || expanded.start_with?("#{root}/")
    end

    raise RobotLab::ToolError, "path escapes the working directory: #{path}"
  end

  def resolve_read_root(path)
    tight = File.expand_path(path.to_s, cwd)

    # cwd is always readable.
    return tight if tight == cwd || tight.start_with?("#{cwd}/")

    expanded = File.expand_path(path.to_s, cwd)

    # AGENT_READABLE_ROOT entries (colon- or comma-delimited).
    readable_roots.each do |root|
      return expanded if expanded == root || expanded.start_with?("#{root}/")
    end

    # Also allow all bundled gem paths.
    read_roots.each do |root|
      return expanded if expanded == root || expanded.start_with?("#{root}/")
    end

    raise RobotLab::ToolError, "path escapes the working directory: #{path}"
  end

  def self.read_roots
    # Memoized class-level set of bundled gem paths (loose + root levels).
    @_coding_tool_read_roots ||= begin
      paths = []
      if defined?(Bundler) && Bundler.respond_to?(:load)
        specs = Bundler.load.specs
        return paths unless specs

        paths.concat(specs.map { |s| s.full_gem_path }.uniq)
      end
      paths
    end
  end

  def self.readable_roots
    # Directories from AGENT_READABLE_ROOT (colon- or comma-delimited).
    @_coding_tool_readable_roots ||= begin
      raw = ENV.fetch("AGENT_READABLE_ROOT", "")
      next_result = []
      if raw.strip.empty?
        next_result
      else
        raw.tr(",", "\n")
           .split("\n")
           .map(&:strip)
           .reject { |r| r.empty? }
           .map { |r| File.expand_path(r) }
      end
    end
  end

  # Instance methods delegate to class-level memoized data.
  def read_roots
    self.class.read_roots
  end

  def readable_roots
    self.class.readable_roots
  end
end
