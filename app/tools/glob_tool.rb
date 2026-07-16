class GlobTool < CodingTool
  description "Find files matching a glob pattern (e.g. '**/*.rb') within the working directory."
  param :pattern, type: "string", desc: "Glob pattern, relative to the working directory (or to path if given)."
  param :path, type: "string", desc: "Subdirectory to search within, relative to the working directory.", required: false

  def execute(pattern:, path: ".")
    base = resolve_path(path)
    raise RobotLab::ToolError, "no such directory: #{path}" unless File.directory?(base)

    matches = Dir.glob(File.join(base, pattern))
    matches.map { |m| m.delete_prefix("#{cwd}/") }.join("\n")
  end
end
