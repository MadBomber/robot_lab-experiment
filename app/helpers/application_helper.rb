module ApplicationHelper
  # Rails flash key -> poetry toast variant, for the layout's flash -> toast
  # recipe. :destructive announces assertively, so it is reserved for alerts;
  # unknown keys fall back to the neutral default treatment.
  FLASH_TOAST_VARIANTS = {
    "alert"  => :destructive,
    "notice" => :success
  }.freeze

  def flash_toast_variant(kind)
    FLASH_TOAST_VARIANTS[kind.to_s] || :default
  end

  # How many attention cards the sidebar queue shows before deferring to the
  # task tables for the rest.
  ATTENTION_QUEUE_LIMIT = 4

  # Tasks waiting on a human, fleet-wide: blocked (except abandoned -- the
  # human already decided) or holding a plan that awaits review. Fuels the
  # sidebar's "Needs you" queue on every page.
  def attention_tasks
    @attention_tasks ||= Task.where(status: "in_review")
                             .or(Task.where.not(blocked_reason: [nil, "abandoned"]))
                             .includes(:project, :agent_runs)
                             .order(updated_at: :desc)
                             .limit(ATTENTION_QUEUE_LIMIT)
                             .to_a
  end

  def fleet_running_count
    @fleet_running_count ||= AgentRun.where(status: "running").count
  end

  def fleet_blocked_count
    @fleet_blocked_count ||= Task.where.not(blocked_reason: [nil, "abandoned"]).count
  end

  # Projects for the sidebar's default navigation section.
  def sidebar_projects
    @sidebar_projects ||= Project.order(:name).to_a
  end

  # Project ids with an agent run in flight -- the sidebar's ACTIVE/IDLE word.
  def active_project_ids
    @active_project_ids ||= AgentRun.where(status: "running")
                                    .joins(:task)
                                    .distinct
                                    .pluck(Task.arel_table[:project_id])
                                    .to_set
  end
end
