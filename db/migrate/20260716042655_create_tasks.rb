class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :project, null: false, foreign_key: true

      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.string :branch_name
      t.string :worktree_path

      # Workflow flags -- the orchestrator's entire memory of pipeline position.
      # See AgentRunCompletionHandler; never inferred from agent prose.
      t.boolean :planning_complete, null: false, default: false
      t.boolean :workflow_complete, null: false, default: false
      t.string :blocked_reason
      t.integer :workflow_run_count, null: false, default: 0
      t.boolean :pr_agent_complete, null: false, default: false

      t.timestamps
    end

    add_index :tasks, :status
  end
end
