class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :task, null: false, foreign_key: true

      # Stamped at creation, never re-derived -- resume must be deterministic.
      t.string :provider, null: false
      t.string :model, null: false
      t.string :effort
      t.datetime :started_at, null: false

      t.timestamps
    end
  end
end
