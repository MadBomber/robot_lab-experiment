class Task < ApplicationRecord
  MAX_WORKFLOW_RUNS = 25

  BLOCKED_REASONS = %w[human_requested max_iterations].freeze

  belongs_to :project
  has_many :conversations, dependent: :destroy
  has_many :agent_runs, dependent: :destroy

  # Not persisted -- only carries the New Task form's description through to
  # TaskDocument.seed (and back to the form on a validation-error re-render).
  attr_accessor :description

  enum :status, { pending: "pending", in_progress: "in_progress", in_review: "in_review", completed: "completed" },
       default: "pending"
  enum :task_kind, { fix: "fix", audit: "audit" }, default: "fix"

  validates :title, presence: true
  validates :blocked_reason, inclusion: { in: BLOCKED_REASONS }, allow_nil: true

  def blocked?
    blocked_reason.present?
  end

  def running_agent_run
    agent_runs.find_by(status: "running")
  end

  def iteration_cap_reached?
    workflow_run_count >= MAX_WORKFLOW_RUNS
  end

  def effective_cwd
    worktree_path.presence || project.effective_cwd
  end

  # The single next manual action available, if any -- everything else
  # (implementation <-> review alternation, workflow_complete -> pr) chains
  # automatically via AgentRunCompletionHandler. Mirrors the same flags the
  # handler reads, so the UI never has its own separate notion of state.
  def runnable_agent_types
    return [] if running_agent_run || pr_agent_complete? || blocked?
    return audit_runnable_types if audit?
    return ["planning"] unless planning_complete?
    return ["implementation"] unless workflow_complete?

    ["pr"]
  end

  def unblock!
    update!(blocked_reason: nil)
  end

  private

  def audit_runnable_types
    agent_runs.audit.exists? ? [] : ["audit"]
  end
end
