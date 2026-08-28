class AddIndexOnBlockedRunIdToTasks < ActiveRecord::Migration[8.1]
  def change
    add_index :tasks, :blocked_run_id
  end
end
