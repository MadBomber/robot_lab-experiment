# Creates a Task together with its supporting filesystem state -- git worktree
# and seeded task doc -- as a single logical unit, shared by TasksController
# and AuditTasksController (see #44).
#
# A DB transaction can't protect this the way it looks like it should:
# WorktreeService#create and TaskDocument.seed are filesystem operations, and
# a transaction rollback never touches the filesystem. Wrapping them in the
# same ActiveRecord::Base.transaction as the Task save (the naive fix) doesn't
# actually fix anything -- if the later filesystem step fails, the DB row
# rolls back correctly, but the worktree directory created earlier in that
# same transaction is still sitting on disk, now orphaned from a Task that no
# longer exists. Same shape of problem as the one already fixed on the
# teardown side in ProjectDestructionService, just mirrored: don't rely on
# rollback for filesystem side effects, explicitly clean up whatever *was*
# already created once a later step fails.
class TaskCreationService
  class Error < StandardError; end

  def initialize(project, attributes:, original_request:)
    @project = project
    @attributes = attributes
    @original_request = original_request
  end

  def call
    task = save_task!
    create_worktree!(task)
    seed_doc!(task)
    task
  end

  private

  def save_task!
    @project.tasks.create!(@attributes)
  rescue ActiveRecord::RecordInvalid => e
    raise Error, e.message
  end

  def create_worktree!(task)
    WorktreeService.new(task).create
  rescue WorktreeService::Error => e
    cleanup!(task)
    raise Error, e.message
  end

  def seed_doc!(task)
    TaskDocument.seed(task, @original_request)
  rescue => e
    cleanup!(task)
    raise Error, "Could not create task document: #{e.message}"
  end

  # Best-effort teardown of whatever a failed step already produced, so a
  # failure at any point leaves no orphaned Task row or worktree behind. Each
  # step is independently rescued -- a worktree removal failure must not skip
  # the doc/DB cleanup that follows it, and vice versa -- and every failure is
  # logged rather than raised, so a secondary cleanup failure here never masks
  # the original error the caller is about to raise. Destroying the Task row
  # is attempted last and always, even if the filesystem steps before it
  # failed: a stray leftover worktree/doc is the much smaller problem (see
  # ProjectDestructionService for the same trade-off on teardown), and an
  # orphaned Task row is exactly the bug this service exists to prevent.
  def cleanup!(task)
    remove_worktree(task)
    delete_doc(task)
    destroy_task(task)
  end

  def remove_worktree(task)
    WorktreeService.new(task).remove
  rescue => e
    Rails.logger.error("TaskCreationService: worktree cleanup failed for task #{task.id}: #{e.message}")
  end

  def delete_doc(task)
    TaskDocument.delete_archive(task)
  rescue => e
    Rails.logger.error("TaskCreationService: task doc cleanup failed for task #{task.id}: #{e.message}")
  end

  def destroy_task(task)
    task.destroy!
  rescue => e
    Rails.logger.error("TaskCreationService: could not destroy task #{task.id} during cleanup: #{e.message}")
  end
end
