class TasksController < ApplicationController
  before_action :set_project
  before_action :set_task, only: %i[show unblock]

  def new
    @task = @project.tasks.new
  end

  def create
    @task = @project.tasks.new(title: task_params[:title])

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

  def unblock
    @task.unblock!
    redirect_to [@project, @task], notice: "Task unblocked."
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
end
