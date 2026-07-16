class AuditTasksController < ApplicationController
  def create
    project = Project.find(params[:project_id])
    task = nil

    ActiveRecord::Base.transaction do
      task = project.tasks.create!(
        title: "Self-audit #{Time.current.strftime('%Y-%m-%d %H:%M')}", task_kind: "audit"
      )
      WorktreeService.new(task).create
    end
    TaskDocument.seed(task, "Self-audit: investigate this codebase and file a GitHub " \
                            "issue for each concrete, verifiable problem found.")

    redirect_to [project, task], notice: "Self-audit task created."
  rescue ActiveRecord::RecordInvalid, WorktreeService::Error => e
    redirect_to project, alert: "Could not start self-audit: #{e.message}"
  end
end
