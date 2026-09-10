class AddGithubIssueNumberToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :github_issue_number, :integer
    add_index :tasks, %i[project_id github_issue_number]
  end
end
