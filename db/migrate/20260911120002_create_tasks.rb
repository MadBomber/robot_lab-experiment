class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      # No standalone project_id index: the [project_id, github_issue_number]
      # composite below covers project_id lookups.
      t.references :project, null: false, foreign_key: true, index: false

      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.string :task_kind, null: false, default: "fix"
      t.string :branch_name
      t.string :worktree_path

      # Workflow flags -- the orchestrator's entire memory of pipeline position.
      # See AgentRunCompletionHandler; never inferred from agent prose.
      t.boolean :planning_complete, null: false, default: false
      t.boolean :workflow_complete, null: false, default: false
      t.string :blocked_reason
      t.text :blocked_detail
      t.integer :blocked_run_id
      t.integer :workflow_run_count, null: false, default: 0
      t.boolean :pr_agent_complete, null: false, default: false

      # Cross-run plateau detection: the last computed progress fingerprint and
      # how many consecutive completion cycles it has stayed unchanged (see
      # AgentRunCompletionHandler / ProgressFingerprint).
      t.string :progress_fingerprint
      t.integer :no_progress_streak, null: false, default: 0

      # Human course-corrections consumed by exactly one subsequent run.
      t.text :pending_guidance

      t.integer :github_issue_number

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :blocked_run_id
    add_index :tasks, %i[project_id github_issue_number]
  end
end
