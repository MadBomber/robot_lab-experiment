class Task < ApplicationRecord
  MAX_WORKFLOW_RUNS = 25

  # Block a task once its progress fingerprint has repeated unchanged this many
  # consecutive completion cycles (the first sighting establishes it, so this is
  # roughly two full impl<->review cycles of no movement) -- see #record_progress!.
  NO_PROGRESS_LIMIT = 3

  BLOCKED_REASONS = %w[human_requested max_iterations no_progress abandoned].freeze

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
    update!(blocked_reason: nil, no_progress_streak: 0)
  end

  # Record this cycle's progress fingerprint, growing the no-progress streak when
  # it's unchanged from last cycle and resetting it when the task moved. Pair with
  # #plateaued? to decide whether to stop chaining. See ProgressFingerprint.
  def record_progress!(fingerprint)
    if fingerprint == progress_fingerprint
      increment!(:no_progress_streak)
    else
      update!(progress_fingerprint: fingerprint, no_progress_streak: 0)
    end
  end

  # The progress fingerprint has stayed unchanged long enough that the pipeline is
  # oscillating without moving forward -- the caller should block the task.
  def plateaued?
    no_progress_streak >= NO_PROGRESS_LIMIT
  end

  # The status enum is display-only state derived from the same flags
  # runnable_agent_types uses -- it never drives branching logic itself, so
  # it's safe to recompute freely without touching the real state machine.
  def derived_status
    return "pending" unless agent_runs.exists?
    return "completed" if pipeline_complete?
    return "in_review" if awaiting_implementation_kickoff?

    "in_progress"
  end

  def recompute_status!
    update!(status: derived_status) unless status == derived_status
  end

  private

  def audit_runnable_types
    agent_runs.audit.exists? ? [] : ["audit"]
  end

  def pipeline_complete?
    audit? ? agent_runs.audit.completed.exists? : pr_agent_complete?
  end

  def awaiting_implementation_kickoff?
    planning_complete? && !agent_runs.implementation.exists?
  end
end
