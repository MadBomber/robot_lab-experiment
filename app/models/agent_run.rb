class AgentRun < ApplicationRecord
  belongs_to :task
  belongs_to :conversation

  enum :agent_type, { planning: "planning", implementation: "implementation", review: "review", pr: "pr", audit: "audit" }
  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed", blocked: "blocked" },
       default: "pending"
end
