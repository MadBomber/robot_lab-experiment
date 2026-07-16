class AddTaskKindToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :task_kind, :string, null: false, default: "fix"
  end
end
