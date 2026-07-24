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
    full = File.expand_path(path.to_s, cwd)
    real = realpath_of_deepest_existing(full)
    unless confined_by_realpath?(real)
      raise RobotLab::ToolError, "path escapes the working directory: #{path}"
    end

    full
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

  # Returns true when +full_path+ (which must be absolute) resolves to a real
  # location within the read scope permitted by the current sandbox level.
  def read_scoped?(full_path)
    return true if sandbox_level == "none"

    real = realpath_of_deepest_existing(full_path)
    cwd_real = File.realpath(cwd)
    roots = case sandbox_level
            when "loose" then [cwd_real] + realpath_roots(read_roots)
            when "root"  then [cwd_real] + realpath_roots(read_roots) + realpath_roots(readable_roots)
            else              [cwd_real]
            end
    confined_by_realpath?(real, roots)
  end

  # cwd is always allowed; otherwise the path must live under one of +extra_roots+
  # (empty for cwd-only confinement, which is every write and the tight read).
  def resolve_confined(path, extra_roots = [])
    full = File.expand_path(path.to_s, cwd)
    real = realpath_of_deepest_existing(full)
    roots = [File.realpath(cwd)] + realpath_roots(extra_roots)
    unless confined_by_realpath?(real, roots)
      raise RobotLab::ToolError, "path escapes the working directory: #{path}"
    end

    full
  end

  # Walks from +expanded_path+ toward the filesystem root and returns the
  # File.realpath of the first ancestor that actually exists. If no ancestor
  # exists, falls back to the cwd's realpath (which always exists in practice).
  def realpath_of_deepest_existing(expanded_path)
    path = expanded_path
    until File.exist?(path)
      parent = File.dirname(path)
      break if parent == path

      path = parent
    end
    File.exist?(path) ? File.realpath(path) : File.realpath(cwd)
  end

  # Returns true when +real_path+ is equal to +root+ or contained beneath it.
  # +extra_roots+ are normalized through File.realpath (non-existent roots are
  # ignored) and +root+ is always the realpath of cwd.
  def confined_by_realpath?(real_path, extra_roots = [])
    ([File.realpath(cwd)] + realpath_roots(extra_roots)).any? do |root|
      real_path == root || real_path.start_with?("#{root}/")
    end
  end

  # Normalize a list of candidate roots via File.realpath, skipping any that do
  # not exist on disk (a non-existent root cannot grant extra read access).
  def realpath_roots(roots)
    roots.map { |r| File.realpath(r) rescue nil }.compact.uniq
  end

  # Instance methods delegate to class-level memoized data.
  def read_roots
    self.class.read_roots
  end

  def readable_roots
    self.class.readable_roots
  end
end
