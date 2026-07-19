class AddBlockedDetailToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :blocked_detail, :text
    add_column :tasks, :blocked_run_id, :integer
  end
end
