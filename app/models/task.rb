class Task < ApplicationRecord
  MAX_WORKFLOW_RUNS = 25

  # Block a task once its progress fingerprint has repeated unchanged this many
  # consecutive completion cycles (the first sighting establishes it, so this is
  # roughly two full impl<->review cycles of no movement) -- see #record_progress!.
  NO_PROGRESS_LIMIT = 3

  BLOCKED_REASONS = %w[human_requested max_iterations no_progress abandoned].freeze

  belongs_to :project
  has_many :conversations, dependent: :destroy
  has_many :agent_runs, dependent: :delete_all

  delegate :llm_provider, :llm_model, to: :project

  # Not persisted -- only carries the New Task form's description through to
  # TaskDocument.seed (and back to the form on a validation-error re-render).
  attr_accessor :description

  enum :status, { pending: "pending", in_progress: "in_progress", in_review: "in_review", completed: "completed" },
       default: "pending"
  enum :task_kind, { fix: "fix", audit: "audit" }, default: "fix"

  validates :title, presence: true
  validates :blocked_reason, inclusion: { in: BLOCKED_REASONS }, allow_nil: true
  validates :status, :task_kind, presence: true
  validates :workflow_run_count, :no_progress_streak, presence: true
  # presence: true would reject `false` (false.present? is false) -- these are
  # booleans, so validate against the pair of legal values instead.
  validates :planning_complete, :workflow_complete, :pr_agent_complete, inclusion: { in: [true, false] }

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

  # The four fix-pipeline stages in order, for the UI's stepper. Audit tasks
  # follow a different single-stage flow and aren't represented here.
  PIPELINE_STAGES = %w[planning implementation review pr].freeze

  # The agent_type the pipeline is on right now, or nil once it's finished.
  # Mirrors the same flags #runnable_agent_types reads, so the stepper never
  # invents its own notion of "where we are."
  def current_pipeline_stage
    return running_agent_run.agent_type if running_agent_run
    return "planning" unless planning_complete?
    return agent_runs.order(:created_at).last&.agent_type || "implementation" unless workflow_complete?
    return "pr" unless pr_agent_complete?

    nil
  end

  # :done / :active / :pending for one stage, for the stepper to color.
  # Implementation and review share one "done" signal (workflow_complete)
  # since they alternate rather than complete independently -- see
  # AgentRunCompletionHandler.
  def pipeline_stage_status(stage)
    case stage
    when "planning"
      planning_complete? ? :done : stage_active_or_pending(stage)
    when "implementation", "review"
      workflow_complete? ? :done : stage_active_or_pending(stage)
    when "pr"
      pr_agent_complete? ? :done : stage_active_or_pending(stage)
    end
  end

  def unblock!
    update!(blocked_reason: nil, blocked_detail: nil, blocked_run_id: nil, no_progress_streak: 0)
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

  def stage_active_or_pending(stage)
    current_pipeline_stage == stage ? :active : :pending
  end

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
