class EditFileTool < CodingTool
  description "Replace an exact string in a file with another string. By default old_string must occur exactly once."
  param :path, type: "string", desc: "Path to the file, relative to the working directory."
  param :old_string, type: "string", desc: "The exact text to find and replace."
  param :new_string, type: "string", desc: "The replacement text."
  param :replace_all, type: "boolean", desc: "Replace every occurrence instead of requiring exactly one.", required: false

  # replace_all defaults to nil (an omitted optional param); nil and false
  # behave identically here.
  def execute(path:, old_string:, new_string:, replace_all: nil)
    full = resolve_write_path(path)
    content = read_target(full, path)
    occurrences = occurrences_of(content, old_string, path)
    raise_not_unique(path, occurrences) if occurrences > 1 && !replace_all

    # gsub covers the non-replace_all case too: the guard above means a lone
    # occurrence is all that's left to replace. Block form so backslash
    # sequences in new_string (\0, \1, ...) are treated as literal text
    # instead of regexp backreferences.
    File.write(full, content.gsub(old_string) { new_string })
    "Replaced #{occurrences} occurrence(s) in #{path}"
  end

  private

  def read_target(full, path)
    raise RobotLab::ToolError, "no such file: #{path}" unless File.file?(full)

    File.read(full)
  end

  def occurrences_of(content, old_string, path)
    occurrences = content.scan(old_string).size
    raise RobotLab::ToolError, "old_string not found in #{path}" if occurrences.zero?

    occurrences
  end

  def raise_not_unique(path, occurrences)
    raise RobotLab::ToolError,
          "old_string is not unique in #{path} (#{occurrences} matches) -- pass replace_all or a more specific string"
  end
end
