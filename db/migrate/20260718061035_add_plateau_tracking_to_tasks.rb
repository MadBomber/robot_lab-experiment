class AddPlateauTrackingToTasks < ActiveRecord::Migration[8.1]
  def change
    # Cross-run plateau detection: the last computed progress fingerprint and how
    # many consecutive completion cycles it has stayed unchanged (see
    # AgentRunCompletionHandler / ProgressFingerprint).
    add_column :tasks, :progress_fingerprint, :string
    add_column :tasks, :no_progress_streak, :integer, default: 0, null: false
  end
end
