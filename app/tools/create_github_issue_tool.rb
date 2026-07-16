require "open3"

# Files a new issue via `gh issue create`. Caps how many issues a single audit
# run can file -- a backstop against a runaway local model, independent of
# the audit prompt's own "file at most 10" instruction (same idea as
# GrepTool::MAX_MATCHES). The counter is instance-scoped, and tools are
# instantiated fresh per AgentRunJob#perform, so this caps issues per audit
# run, not for the repository's lifetime.
class CreateGithubIssueTool < CodingTool
  MAX_ISSUES_PER_RUN = 10

  description "File a new GitHub issue for a concrete, verified problem found in this repository."
  param :title, type: "string", desc: "A short, specific issue title."
  param :body, type: "string", desc: "The issue body: what's wrong, where (file/line), and how to fix it."

  def initialize(cwd:, robot: nil)
    super
    @filed = 0
  end

  def execute(title:, body:)
    if @filed >= MAX_ISSUES_PER_RUN
      raise RobotLab::ToolError, "already filed #{MAX_ISSUES_PER_RUN} issues this run -- stop here"
    end

    out, err, status = Open3.capture3("gh", "issue", "create", "--title", title, "--body", body, chdir: cwd)
    raise RobotLab::ToolError, "gh issue create failed: #{err}" unless status.success?

    @filed += 1
    "Filed: #{out.strip}"
  end
end
