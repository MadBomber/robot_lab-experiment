class MarkWorkflowBlockedTool < TaskCompletionTool
  description "Call this only when the remaining work genuinely requires a human decision, credential, or external " \
              "action that no agent can perform (BLOCKED). Write the specifics into the task doc's Review Findings " \
              "section first."

  def execute
    task.update!(blocked_reason: "human_requested")
    "Task marked blocked. A human must resolve the noted issue and resume the task."
  end
end
