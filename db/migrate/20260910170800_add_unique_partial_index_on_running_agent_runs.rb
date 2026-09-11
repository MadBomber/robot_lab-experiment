class AddUniquePartialIndexOnRunningAgentRuns < ActiveRecord::Migration[8.1]
  def up
    # Databases that hit the race this index prevents already hold multiple
    # "running" rows for one task -- the unique index would refuse to build on
    # exactly the databases that need it. Keep the newest running row per task
    # and sweep the rest to "failed" (mirroring the boot-time orphan recovery
    # in config/initializers/orphan_agent_run_recovery.rb) before adding the
    # constraint.
    execute <<~SQL
      UPDATE agent_runs
      SET status = 'failed', updated_at = CURRENT_TIMESTAMP
      WHERE status = 'running'
        AND id NOT IN (
          SELECT MAX(id) FROM agent_runs WHERE status = 'running' GROUP BY task_id
        )
    SQL

    add_index :agent_runs, :task_id,
              unique: true,
              where: "status = 'running'",
              name: "index_agent_runs_one_running_per_task"
  end

  def down
    remove_index :agent_runs, name: "index_agent_runs_one_running_per_task"
  end
end
