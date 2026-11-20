class WriteFileTool < CodingTool
  description "Write content to a file within the current working directory, creating it (and any parent directories) if needed."
  parameter :path, type: "string", description: "Path to the file, relative to the working directory."
  parameter :content, type: "string", description: "The full content to write."

  def execute(path:, content:)
    full = resolve_write_path(path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    "Wrote #{content.bytesize} bytes to #{path}"
  end
end
