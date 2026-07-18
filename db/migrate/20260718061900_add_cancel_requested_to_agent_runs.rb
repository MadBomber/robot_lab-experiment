class AddCancelRequestedToAgentRuns < ActiveRecord::Migration[8.1]
  def change
    # Set by the Stop/Abandon controls; AgentRunJob checks it between tool calls
    # and halts the in-flight run cooperatively.
    add_column :agent_runs, :cancel_requested, :boolean, default: false, null: false
  end
end
