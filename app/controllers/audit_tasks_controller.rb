class AuditTasksController < ApplicationController
  def create
    project = Project.find(params[:project_id])
    original_request = "Self-audit: investigate this codebase and file a GitHub " \
                       "issue for each concrete, verifiable problem found."

    task = TaskCreationService.new(
      project,
      attributes: { title: "Self-audit #{Time.current.strftime('%Y-%m-%d %H:%M')}", task_kind: "audit" },
      original_request:
    ).call

    redirect_to [project, task], notice: "Self-audit task created."
  rescue TaskCreationService::Error => e
    redirect_to project, alert: "Could not start self-audit: #{e.message}"
  end
end
