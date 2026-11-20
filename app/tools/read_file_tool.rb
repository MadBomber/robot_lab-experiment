class ReadFileTool < CodingTool
  description "Read the contents of a file within the current working directory."
  parameter :path, type: "string", description: "Path to the file, relative to the working directory."

  def execute(path:)
    full = resolve_read_path(path)
    raise RobotLab::ToolError, "no such file: #{path}" unless File.file?(full)

    File.read(full)
  end
end
