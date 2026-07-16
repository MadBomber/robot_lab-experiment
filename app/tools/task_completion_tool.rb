# Base class for tools an agent calls to signal a workflow-flag transition.
# Unlike Bottega's TypeScript reference (which spawns a subprocess per turn and
# so has agents shell out to a small CLI script to flip DB flags), this port
# runs entirely in-process -- the tool can update ActiveRecord directly. Same
# design principle either way: the agent signals state via an explicit, narrow
# tool call; the orchestrator never parses prose to infer a verdict.
class TaskCompletionTool < TaskScopedTool
end
