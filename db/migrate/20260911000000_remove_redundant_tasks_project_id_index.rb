class RemoveRedundantTasksProjectIdIndex < ActiveRecord::Migration[8.1]
  def change
    # Redundant -- already covered by the composite
    # index_tasks_on_project_id_and_github_issue_number, which leads with the
    # same column.
    remove_index :tasks, name: "index_tasks_on_project_id"
  end
end
