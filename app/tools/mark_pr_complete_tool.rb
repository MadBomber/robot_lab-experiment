class MarkPrCompleteTool < TaskCompletionTool
  description "Call this once the PR is open, CI is green, and it is mergeable. Never call this before all three are true."

  def execute
    task.update!(pr_agent_complete: true)
    "PR marked complete. This task's pipeline is finished; a human will review and merge the PR."
  end
end
