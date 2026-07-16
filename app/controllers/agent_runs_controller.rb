class AgentRunsController < ApplicationController
  def create
    project = Project.find(params[:project_id])
    task = project.tasks.find(params[:task_id])
    agent_type = params[:agent_type]

    unless AgentRun.agent_types.key?(agent_type)
      redirect_to [project, task], alert: "Invalid agent type: #{agent_type}"
      return
    end

    AgentRunner.start_agent_run(task, agent_type)
    redirect_to [project, task], notice: "#{agent_type.to_s.capitalize} agent started."
  rescue AgentRunner::AlreadyRunningError
    redirect_to [project, task], alert: "An agent is already running for this task."
  end
end
