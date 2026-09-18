module TasksHelper
  # Poetry badge variant per task status -- the soft trio plus outline, one
  # treatment family per surface.
  STATUS_BADGE_VARIANTS = {
    "pending"     => :outline,
    "in_progress" => :info,
    "in_review"   => :info,
    "completed"   => :success
  }.freeze

  # The status WORD shown beside its color everywhere -- color alone must
  # never carry status (see .impeccable.md hard rules).
  STATUS_WORDS = {
    "pending"     => "QUEUED",
    "in_progress" => "IN PROGRESS",
    "in_review"   => "IN REVIEW",
    "completed"   => "DONE"
  }.freeze

  # Attention-priority sort weight: what needs a human first.
  ATTENTION_ORDER = %w[blocked running in_review in_progress pending completed].freeze

  PIPELINE_ABBREVS = {
    "planning"       => "PLAN",
    "implementation" => "IMPL",
    "review"         => "REV",
    "pr"             => "PR"
  }.freeze

  STAGE_TITLES = { "pr" => "Pull request" }.freeze

  def task_status_badge_variant(status)
    STATUS_BADGE_VARIANTS[status.to_s] || :outline
  end

  def task_status_word(task)
    return "BLOCKED" if task.blocked?
    return "RUNNING" if task.running_agent_run

    STATUS_WORDS[task.status] || task.status.humanize.upcase
  end

  def task_status_variant(task)
    return :destructive if task.blocked?
    return :warning if task.running_agent_run

    task_status_badge_variant(task.status)
  end

  # The one-line explanation under a task's title in tables and the sidebar.
  def task_status_detail(task)
    return task.blocked_detail.presence || "blocked (#{task.blocked_reason&.humanize&.downcase})" if task.blocked?
    return "#{task.running_agent_run.agent_type} agent working" if task.running_agent_run

    case task.status
    when "in_review"  then "plan awaits your review"
    when "completed"  then "pipeline complete"
    when "pending"    then "not started"
    else                   "waiting for the next run"
    end
  end

  def tasks_by_attention(tasks)
    tasks.sort_by { |task| ATTENTION_ORDER.index(task_attention_key(task)) || ATTENTION_ORDER.length }
  end

  def task_attention_key(task)
    return "blocked" if task.blocked?
    return "running" if task.running_agent_run

    task.status
  end

  def pipeline_stage_title(stage)
    STAGE_TITLES.fetch(stage) { stage.capitalize }
  end

  # [word, poetry badge variant] for one stage of the pipeline tracker.
  def pipeline_stage_badge(task, stage)
    case task.pipeline_stage_status(stage)
    when :done   then ["DONE", :success]
    when :active then active_stage_badge(task)
    else              ["PENDING", :outline]
    end
  end

  # Compact per-row pipeline summary: [abbrev, glyph, css-token classes] per
  # stage. Words + glyphs carry the state; color only reinforces it.
  def task_pipeline_summary(task)
    Task::PIPELINE_STAGES.map do |stage|
      abbrev = PIPELINE_ABBREVS.fetch(stage)
      case task.pipeline_stage_status(stage)
      when :done   then [abbrev, "✓", "text-success"]
      when :active then [abbrev, active_stage_glyph(task), active_stage_classes(task)]
      else              [abbrev, nil, "text-muted-foreground"]
      end
    end
  end

  private

  def active_stage_badge(task)
    return ["STALLED", :destructive] if task.blocked?
    return ["RUNNING", :warning] if task.running_agent_run

    ["UP NEXT", :info]
  end

  def active_stage_glyph(task)
    task.blocked? ? "✕" : "▶"
  end

  def active_stage_classes(task)
    task.blocked? ? "font-semibold text-destructive" : "font-semibold text-warning"
  end
end
