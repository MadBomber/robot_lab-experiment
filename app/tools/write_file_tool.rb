class WriteFileTool < CodingTool
  description "Write content to a file within the current working directory, creating it (and any parent directories) if needed."
  param :path, type: "string", desc: "Path to the file, relative to the working directory."
  param :content, type: "string", desc: "The full content to write."

  def execute(path:, content:)
    full = resolve_path(path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    "Wrote #{content.bytesize} bytes to #{path}"
  end
end
