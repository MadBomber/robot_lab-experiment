class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :repo_folder_path, null: false
      t.string :subproject_path

      # Per-project LLM defaults; fall back to AgentRunner's constants when nil.
      t.string :llm_provider
      t.string :llm_model

      t.timestamps
    end

    add_index :projects, :repo_folder_path, unique: true
  end
end
