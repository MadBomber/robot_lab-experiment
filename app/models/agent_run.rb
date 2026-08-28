class AgentRun < ApplicationRecord
  belongs_to :task
  belongs_to :conversation

  enum :agent_type, { planning: "planning", implementation: "implementation", review: "review", pr: "pr", audit: "audit" }
  enum :status,
       { pending: "pending", running: "running", completed: "completed",
         failed: "failed", blocked: "blocked", cancelled: "cancelled" },
       default: "pending"

  validates :agent_type, :status, presence: true
  # presence: true would reject `false` (false.present? is false) -- this is
  # a boolean, so validate against the pair of legal values instead.
  validates :cancel_requested, inclusion: { in: [true, false] }
end
