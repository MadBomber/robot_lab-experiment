# The entire state machine, in one place, deciding what (if anything) runs
# next after an AgentRun finishes. Reads only Task flags -- never agent
# transcript/prose -- and re-reads the Task fresh so it never trusts a
# possibly-stale in-memory copy. See core/orchestration-loop.md notes in
# shimmying-floating-island.md for the source design this mirrors.
class AgentRunCompletionHandler
  Result = Data.define(:action, :next_agent_run)

  # The human-attention milestones that also broadcast a toast into the
  # layout's #poetry-toaster region. Chained impl<->review hops stay quiet
  # on purpose -- they fire constantly and the task header already shows
  # them. Toasts are supplementary: the same state always lands in the
  # header/sidebar refresh below. A Symbol description names the private
  # method that renders it from run/task state; a String is used verbatim.
  TOAST_EVENTS = {
    stopped_after_planning: { variant: :info, title: "Planning complete",
                              description: "Review the plan, then run implementation." },
    stopped_after_audit:    { variant: :success, title: "Audit finished" },
    failed_no_chain:        { variant: :destructive, title: "Agent run failed",
                              description: :failed_run_description },
    started_pr:             { variant: :info, title: "Review approved",
                              description: "The PR agent is running." },
    already_complete:       { variant: :success, title: "Task complete",
                              description: "The PR agent has finished." },
    blocked_max_iterations: { variant: :warning, title: "Task blocked",
                              description: :blocked_description },
    blocked_no_progress:    { variant: :warning, title: "Task blocked",
                              description: :blocked_description }
  }.freeze

  def self.call(agent_run)
    new(agent_run).call
  end

  def initialize(agent_run)
    @agent_run = agent_run
    @task = agent_run.task.reload
    @task.recompute_status!
  end

  def call
    return no_chain_with_broadcast(:failed_no_chain) if @agent_run.failed?
    return no_chain_with_broadcast(:stopped_after_planning) if @agent_run.planning?
    return no_chain_with_broadcast(:stopped_after_audit) if @agent_run.audit?
    return pr_stage_result if @task.workflow_complete?
    return no_chain_with_broadcast(:stopped_blocked) if @task.blocked?

    stop_if_capped || stop_if_plateaued || chain_next_workflow_run
  end

  private

  # Review has signed off: run the PR agent once, then the task is done.
  def pr_stage_result
    return no_chain_with_broadcast(:already_complete) if @task.pr_agent_complete?

    start_with_broadcast(:pr, :started_pr)
  end

  # Blocks the task with the no-chain Result once it hits the workflow-run
  # cap; nil otherwise so the caller continues.
  def stop_if_capped
    return unless @task.iteration_cap_reached?

    detail = "reached the #{Task::MAX_WORKFLOW_RUNS}-run workflow cap"
    @task.update!(blocked_reason: "max_iterations", blocked_detail: detail, blocked_run_id: @agent_run.id)
    no_chain_with_broadcast(:blocked_max_iterations)
  end

  # The impl<->review alternation: whichever of the two just ran, start the
  # other.
  def chain_next_workflow_run
    next_type = @agent_run.implementation? ? :review : :implementation
    start_with_broadcast(
      next_type,
      next_type == :review ? :chained_to_review : :chained_to_implementation
    )
  end

  # Cross-run plateau: if the task's progress fingerprint hasn't moved for
  # several cycles, the impl<->review loop is oscillating without progress --
  # block now rather than grinding to the iteration cap. Records this cycle's
  # progress and, if the task has plateaued, blocks it and returns the
  # no-chain Result; otherwise returns nil so the caller continues.
  def stop_if_plateaued
    @task.record_progress!(ProgressFingerprint.for(@task))
    return unless @task.plateaued?

    detail = "progress fingerprint unchanged for #{@task.no_progress_streak} cycles"
    @task.update!(blocked_reason: "no_progress", blocked_detail: detail, blocked_run_id: @agent_run.id)
    no_chain_with_broadcast(:blocked_no_progress)
  end

  def start(agent_type, action)
    run = AgentRunner.start_agent_run(@task, agent_type)
    Result.new(action:, next_agent_run: run)
  rescue AgentRunner::AlreadyRunningError
    no_chain(:already_running)
  end

  def no_chain(action)
    Result.new(action:, next_agent_run: nil)
  end

  # --- broadcasting helpers ---

  def start_with_broadcast(agent_type, action)
    result = start(agent_type, action)
    broadcast_task_header(action, result.next_agent_run)
    result
  end

  def no_chain_with_broadcast(action)
    broadcast_task_header(action, nil)
    no_chain(action)
  end

  # Both the stepper/status pill (task-header) and the sidebar's action
  # buttons (task-sidebar, e.g. "Run implementation" appearing once planning
  # stops for review) depend on the same Task state -- refresh both together
  # whenever it changes, so nobody has to reload the page to see them.
  def broadcast_task_header(action, next_agent_run)
    return unless defined?(Turbo::StreamsChannel)

    stream = "task_#{@task.id}"
    broadcast_toast(stream, action)

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "task-header",
      partial: "tasks/task_header",
      locals: { task: @task, project: @task.project }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "task-sidebar",
      partial: "tasks/task_controls",
      locals: { task: @task, project: @task.project, doc_content: TaskDocument.read(@task) }
    )
  end

  def broadcast_toast(stream, action)
    locals = toast_locals(action)
    return unless locals

    Turbo::StreamsChannel.broadcast_append_to(
      stream, target: "poetry-toaster", partial: "shared/toast", locals:
    )
  end

  def toast_locals(action)
    variant, title, description = TOAST_EVENTS[action]&.values_at(:variant, :title, :description)
    return unless title

    { variant:, title:, description: resolve_toast_description(description) }
  end

  def resolve_toast_description(description)
    description.is_a?(Symbol) ? send(description) : description
  end

  def failed_run_description
    "The #{@agent_run.agent_type} run failed -- the pipeline stopped."
  end

  def blocked_description
    @task.blocked_detail
  end
end
