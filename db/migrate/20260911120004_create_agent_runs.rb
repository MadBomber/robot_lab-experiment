class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      # No standalone task_id index: the [task_id, status] composite and the
      # partial unique index below cover task_id lookups.
      t.references :task, null: false, foreign_key: true, index: false
      t.references :conversation, null: false, foreign_key: true, index: { unique: true }

      t.string :agent_type, null: false
      t.string :status, null: false, default: "pending"

      # Set by the controller mid-run; AgentRunJob reloads and raises Cancelled.
      t.boolean :cancel_requested, null: false, default: false

      t.timestamps
    end

    add_index :agent_runs, %i[task_id status]

    # The DB-level half of AgentRunner's "one running agent per task" guard --
    # the in-code check is only a fast path (RecordNotUnique is rescued into
    # AlreadyRunningError).
    add_index :agent_runs, :task_id,
              unique: true,
              where: "status = 'running'",
              name: "index_agent_runs_one_running_per_task"
  end
end
