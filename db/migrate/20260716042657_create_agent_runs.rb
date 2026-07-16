class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.references :task, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true

      t.string :agent_type, null: false
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :agent_runs, %i[task_id status]
  end
end
