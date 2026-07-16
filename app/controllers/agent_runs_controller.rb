class AgentRunsController < ApplicationController
  def create
    project = Project.find(params[:project_id])
    task = project.tasks.find(params[:task_id])

    AgentRunner.start_agent_run(task, params[:agent_type])
    redirect_to [project, task], notice: "#{params[:agent_type].to_s.capitalize} agent started."
  rescue AgentRunner::AlreadyRunningError
    redirect_to [project, task], alert: "An agent is already running for this task."
  end
end
