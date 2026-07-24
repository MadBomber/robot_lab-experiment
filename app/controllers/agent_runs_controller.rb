class AgentRunsController < ApplicationController
  before_action :set_project_and_task

  def create
    agent_type = params[:agent_type]

    unless AgentRun.agent_types.key?(agent_type)
      redirect_to [@project, @task], alert: "Invalid agent type: #{agent_type}"
      return
    end

    AgentRunner.start_agent_run(@task, agent_type)
    redirect_to [@project, @task], notice: "#{agent_type.to_s.capitalize} agent started."
  rescue AgentRunner::AlreadyRunningError
    redirect_to [@project, @task], alert: "An agent is already running for this task."
  end

  def show
    @agent_run = @task.agent_runs.find(params[:id])
    @messages = Message.where(conversation_id: @agent_run.conversation_id).order(:created_at, :seq)
  end

  private

  def set_project_and_task
    @project = Project.find(params[:project_id])
    @task = @project.tasks.find(params[:task_id])
  end
end
