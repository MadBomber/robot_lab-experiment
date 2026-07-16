class EditFileTool < CodingTool
  description "Replace an exact string in a file with another string. By default old_string must occur exactly once."
  param :path, type: "string", desc: "Path to the file, relative to the working directory."
  param :old_string, type: "string", desc: "The exact text to find and replace."
  param :new_string, type: "string", desc: "The replacement text."
  param :replace_all, type: "boolean", desc: "Replace every occurrence instead of requiring exactly one.", required: false

  def execute(path:, old_string:, new_string:, replace_all: false)
    full = resolve_path(path)
    raise RobotLab::ToolError, "no such file: #{path}" unless File.file?(full)

    content = File.read(full)
    occurrences = content.scan(old_string).size
    raise RobotLab::ToolError, "old_string not found in #{path}" if occurrences.zero?
    if occurrences > 1 && !replace_all
      raise RobotLab::ToolError,
            "old_string is not unique in #{path} (#{occurrences} matches) -- pass replace_all or a more specific string"
    end

    # Block form so backslash sequences in new_string (\0, \1, ...) are treated
    # as literal text instead of regexp backreferences.
    updated = replace_all ? content.gsub(old_string) { new_string } : content.sub(old_string) { new_string }
    File.write(full, updated)
    "Replaced #{replace_all ? occurrences : 1} occurrence(s) in #{path}"
  end
end
