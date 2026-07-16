# Thin ActiveJob wrapper around AgentRunCompletionHandler -- exists only so the
# handler can be scheduled with a settle delay after an AgentRun finishes.
class AgentRunCompletionJob < ApplicationJob
  queue_as :default

  def perform(agent_run_id)
    AgentRunCompletionHandler.call(AgentRun.find(agent_run_id))
  end
end
