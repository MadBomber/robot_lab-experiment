require "open3"
require "json"

class ListGithubIssuesTool < CodingTool
  description "List currently open GitHub issues in this repository, to avoid filing duplicates."

  def execute
    out, err, status = Open3.capture3("gh", "issue", "list", "--state", "open", "--json", "number,title", chdir: cwd)
    raise RobotLab::ToolError, "gh issue list failed: #{err}" unless status.success?

    # --json always emits a JSON array (e.g. "[]" when empty), so the raw string
    # is never blank -- parse it into a readable list instead of handing the
    # agent raw JSON, and detect "none" from the parsed array, not string blankness.
    issues = JSON.parse(out.presence || "[]")
    return "No open issues." if issues.empty?

    issues.map { |issue| "##{issue['number']} #{issue['title']}" }.join("\n")
  rescue JSON::ParserError => e
    raise RobotLab::ToolError, "could not parse gh issue list output: #{e.message}"
  end
end
