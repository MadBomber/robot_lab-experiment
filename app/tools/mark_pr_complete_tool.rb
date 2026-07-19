require "open3"
require "json"

# Terminal completion signal for the PR stage. Unlike the other completion
# tools, this one does not blindly trust the agent's word: it verifies that the
# stage actually produced its artifacts before flipping the flag. A small model
# can otherwise call mark_pr_complete while work sits uncommitted and no PR
# exists (see task #29), and the orchestrator -- which by design never parses
# prose to infer a verdict -- would accept that false "done." The verdict is
# still a narrow, explicit tool call; the tool just refuses to lie.
#
# Adaptive strictness: when a GitHub remote is configured an open PR is
# required; on a remote-less checkout a committed branch is the deliverable.
class MarkPrCompleteTool < TaskCompletionTool
  description "Call this once the PR is open, CI is green, and it is mergeable. " \
              "This tool verifies your work is committed and (when a GitHub remote " \
              "exists) that an open PR is present before accepting completion; if " \
              "something is missing it returns what you must do next instead of completing."

  def execute
    blocker = unmet_requirement
    return blocker if blocker

    task.update!(pr_agent_complete: true)
    "PR marked complete. This task's pipeline is finished; a human will review and merge the PR."
  end

  # The first unmet artifact requirement as a human-actionable string, or nil
  # when the task is genuinely ready to be marked complete. Ordered cheapest and
  # most-common failure first so the agent gets the single next action to take.
  def unmet_requirement
    if dirty_worktree?
      return "You still have uncommitted changes in the worktree. Commit them " \
             "(and push the branch) before calling mark_pr_complete."
    end

    # Nothing committed beyond the base branch and nothing uncommitted => there
    # is genuinely nothing to submit; completing is correct.
    return nil unless commits_ahead?

    # No GitHub remote: a committed branch is the deliverable, nothing to push.
    return nil unless remote_configured?

    unless open_pr?
      return "Your changes are committed but no open PR exists for branch " \
             "#{task.branch_name}. Push the branch and open a PR (gh pr create) " \
             "before calling mark_pr_complete."
    end

    nil
  end

  # --- individual ground-truth checks (each independently testable) ---

  def dirty_worktree?
    out, _err, status = Open3.capture3("git", "status", "--porcelain", chdir: cwd)
    status.success? && !out.strip.empty?
  end

  def commits_ahead?
    out, _err, status = Open3.capture3("git", "rev-list", "--count", "HEAD", "--not", base_branch, chdir: cwd)
    status.success? && out.strip.to_i.positive?
  end

  def remote_configured?
    _out, _err, status = Open3.capture3("git", "remote", "get-url", "origin", chdir: cwd)
    status.success?
  end

  def open_pr?
    return false unless task.branch_name?

    out, _err, status = Open3.capture3("gh", "pr", "view", task.branch_name, "--json", "state", chdir: cwd)
    return false unless status.success?

    JSON.parse(out)["state"] == "OPEN"
  rescue StandardError
    false
  end

  def base_branch
    out, _err, status = Open3.capture3("git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD", chdir: cwd)
    return "main" unless status.success?

    out.strip.delete_prefix("origin/").presence || "main"
  end

  private

  def cwd = task.effective_cwd
end
