class FixIndexesFlaggedByActiveRecordDoctor < ActiveRecord::Migration[8.1]
  def change
    # Redundant -- already covered by a composite index that leads with the
    # same column.
    remove_index :messages, name: "index_messages_on_conversation_id"
    remove_index :agent_runs, name: "index_agent_runs_on_task_id"

    # Conversation has_one :agent_run without a unique index could let two
    # AgentRuns attach to the same Conversation.
    remove_index :agent_runs, name: "index_agent_runs_on_conversation_id"
    add_index :agent_runs, :conversation_id, unique: true
  end
end
