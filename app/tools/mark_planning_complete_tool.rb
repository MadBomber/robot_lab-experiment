class MarkPlanningCompleteTool < TaskCompletionTool
  description "Call this once the plan has been written to the task doc and is ready for human review. " \
              "Do not call this until the plan doc is fully written and verified by reading it back."

  def execute
    task.update!(planning_complete: true)
    "Plan marked complete. The task will now wait for a human to review it."
  end
end
