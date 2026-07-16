require "open3"

class ListGithubIssuesTool < CodingTool
  description "List currently open GitHub issues in this repository, to avoid filing duplicates."

  def execute
    out, err, status = Open3.capture3("gh", "issue", "list", "--state", "open", "--json", "number,title", chdir: cwd)
    raise RobotLab::ToolError, "gh issue list failed: #{err}" unless status.success?

    out.strip.presence || "No open issues."
  end
end
