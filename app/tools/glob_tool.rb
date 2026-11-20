class GlobTool < CodingTool
  description "Find files matching a glob pattern (e.g. '**/*.rb') within the working directory."
  parameter :pattern, type: "string", description: "Glob pattern, relative to the working directory (or to path if given)."
  parameter :path, type: "string", description: "Subdirectory to search within, relative to the working directory.", required: false

  def execute(pattern:, path: ".")
    base = resolve_read_path(path)
    raise RobotLab::ToolError, "no such directory: #{path}" unless File.directory?(base)

    matches = Dir.glob(File.join(base, pattern)).select { |m| read_scoped?(m) }
    matches.map { |m| m.delete_prefix("#{cwd}/") }.join("\n")
  end
end
