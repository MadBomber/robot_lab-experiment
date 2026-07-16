class MarkWorkflowCompleteTool < TaskCompletionTool
  description "Call this only when every to-do item has been verified against the plan and all tests pass (READY)."

  def execute
    task.update!(workflow_complete: true)
    "Workflow marked complete (READY). The PR agent will start next."
  end
end
