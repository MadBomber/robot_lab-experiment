class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true

      # Idempotent append: retried/duplicated streaming events upsert on uuid.
      t.string :uuid, null: false
      # App-assigned, monotonic per conversation -- never DB autoincrement,
      # since ordering must be stable across idempotent re-inserts.
      t.integer :seq, null: false
      t.string :msg_type, null: false
      t.json :payload, null: false, default: {}

      t.timestamps
    end

    add_index :messages, %i[conversation_id uuid], unique: true
    add_index :messages, %i[conversation_id seq]
  end
end
