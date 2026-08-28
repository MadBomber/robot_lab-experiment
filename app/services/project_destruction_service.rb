# Deletes a Project and everything under it. DB destruction (Project -> Tasks
# -> Conversations/AgentRuns via `dependent:` associations, see Project/Task
# models) happens first and must commit on its own before any filesystem work
# starts -- worktree removal and archive deletion are irreversible, so running
# them inside the same transaction as the destroy (the old approach) meant a
# later failure could roll back the DB rows while the filesystem side effects
# from earlier tasks stayed gone, leaving DB and filesystem inconsistent with
# no way back. Once the destroy has committed, a filesystem cleanup failure for
# one task is a much smaller problem (a stray leftover worktree/archive) and
# must not block cleanup of the rest -- mirrors the best-effort sweep pattern
# in TasksController#clear_completed.
class ProjectDestructionService
  class Error < StandardError; end

  def initialize(project)
    @project = project
  end

  def call
    tasks = @project.tasks.to_a
    project_name = @project.name

    destroy_project!(project_name)

    failed = tasks.reject { |task| cleanup_task_filesystem(task) }
    return if failed.empty?

    raise Error, "Project '#{project_name}' was deleted, but filesystem cleanup failed for " \
                 "#{failed.size} #{'task'.pluralize(failed.size)} (task ids: #{failed.map(&:id).join(', ')})"
  end

  private

  def destroy_project!(project_name)
    ActiveRecord::Base.transaction do
      @project.destroy!
    end
  rescue => e
    raise Error, "Could not destroy project '#{project_name}': #{e.message}"
  end

  # Best-effort: returns whether the task's filesystem state was cleaned up,
  # logging (not raising) so one stuck task doesn't block cleanup of the rest.
  def cleanup_task_filesystem(task)
    WorktreeService.new(task).remove
    TaskDocument.delete_archive(task)
    true
  rescue => e
    Rails.logger.error("ProjectDestructionService: could not clean up task #{task.id} filesystem: #{e.message}")
    false
  end
end
