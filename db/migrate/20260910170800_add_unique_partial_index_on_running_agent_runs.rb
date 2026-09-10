class AddUniquePartialIndexOnRunningAgentRuns < ActiveRecord::Migration[8.1]
  def change
    add_index :agent_runs, :task_id,
              unique: true,
              where: "status = 'running'",
              name: "index_agent_runs_one_running_per_task"
  end
end
