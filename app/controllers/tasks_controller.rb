class TasksController < ApplicationController
  before_action :set_project
  before_action :set_task, only: %i[show destroy unblock pause stop abandon update_status heartbeat]

  def new
    @task = @project.tasks.new
    prefill_from_issue(params[:from_issue])
  end

  def create
    @task = @project.tasks.new(title: task_params[:title], description: task_params[:description])

    ActiveRecord::Base.transaction do
      @task.save!
      WorktreeService.new(@task).create
    end
    TaskDocument.seed(@task, task_params[:description].presence || @task.title)

    redirect_to [@project, @task], notice: "Task created."
  rescue ActiveRecord::RecordInvalid, WorktreeService::Error => e
    @task.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  def show
    @doc_content = TaskDocument.read(@task)
    @messages = Message.where(conversation_id: @task.conversation_ids).order(:created_at, :seq)
  end

  def destroy
    delete_task!(@task)
    redirect_to @project, notice: "Task '#{@task.title}' deleted."
  rescue => e
    redirect_to @project, alert: "Could not delete task: #{e.message}"
  end

  def clear_completed
    tasks = @project.tasks.completed.to_a
    # One task that fails to tear down (e.g. a stuck worktree, now that
    # WorktreeService#remove surfaces those) must not abort the whole sweep.
    failed = tasks.reject { |task| destroy_task(task) }
    cleared = tasks.size - failed.size

    notice = "Cleared #{cleared} completed #{'task'.pluralize(cleared)}."
    notice += " #{failed.size} could not be deleted." if failed.any?
    redirect_to @project, notice:
  end

  def unblock
    @task.unblock!
    redirect_to [@project, @task], notice: "Task resumed."
  end

  # Stop auto-chaining but let the current run finish naturally.
  def pause
    @task.update!(blocked_reason: "human_requested")
    redirect_to [@project, @task], notice: "Task paused -- it won't start another run."
  end

  # Halt the in-flight run now (cooperative cancel) and pause the pipeline.
  def stop
    request_cancel(@task.running_agent_run)
    @task.update!(blocked_reason: "human_requested")
    redirect_to [@project, @task], notice: "Stopping the current run."
  end

  # Give up on the task: halt any in-flight run and mark it abandoned.
  def abandon
    request_cancel(@task.running_agent_run)
    @task.update!(blocked_reason: "abandoned")
    redirect_to [@project, @task], notice: "Task abandoned."
  end

  # Manual escape hatch: the normal status is derived automatically from
  # pipeline flags (see Task#recompute_status!), but a human sometimes needs
  # to override it directly -- e.g. abandoning a task outside the pipeline.
  def update_status
    @task.update!(status: params.require(:status))
    redirect_to [@project, @task], notice: "Task status set to #{@task.status}."
  rescue ArgumentError
    redirect_to [@project, @task], alert: "'#{params[:status]}' is not a valid status."
  end

  def heartbeat
    conversation = @task.conversations.order(created_at: :desc).first
    if conversation
      last_msg = conversation.messages.maximum(:created_at)
      render json: {
        started_at: conversation.started_at.to_s,
        message_count: conversation.messages.count,
        last_message_created_at: last_msg&.to_s
      }
    else
      render json: { started_at: nil, message_count: 0, last_message_created_at: nil }
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_task
    @task = @project.tasks.find(params[:id])
  end

  def task_params
    params.expect(task: %i[title description])
  end

  def delete_task!(task)
    WorktreeService.new(task).remove
    TaskDocument.delete_archive(task)
    task.destroy!
  end

  # Flag an in-flight run for cooperative cancellation; AgentRunJob picks it up
  # between tool calls. No-op when nothing is running.
  def request_cancel(agent_run)
    agent_run&.update!(cancel_requested: true)
  end

  # Best-effort variant for bulk teardown: returns whether the task was deleted,
  # logging (not raising) so one stuck task doesn't abort a clear_completed sweep.
  def destroy_task(task)
    delete_task!(task)
    true
  rescue => e
    Rails.logger.error("clear_completed: could not delete task #{task.id}: #{e.message}")
    false
  end

  def prefill_from_issue(number)
    return if number.blank?

    issue = GithubIssueService.find(@project, number)
    return unless issue

    @task.title = issue.title
    @task.description = "#{issue.body}\n\n(from #{issue.url})"
  end
end
