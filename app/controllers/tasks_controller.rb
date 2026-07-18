class TasksController < ApplicationController
  before_action :set_project
  before_action :set_task, only: %i[show destroy unblock update_status heartbeat]

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
    redirect_to [@project, @task], notice: "Task unblocked."
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
