class AddPendingGuidanceToTasks < ActiveRecord::Migration[8.1]
  def change
    # Human redirect (#23): guidance queued for the task's next run, injected into
    # that run's kickoff message and then cleared. Nil when there's none pending.
    add_column :tasks, :pending_guidance, :text
  end
end
