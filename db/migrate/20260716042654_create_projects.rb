class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :repo_folder_path, null: false
      t.string :subproject_path

      t.timestamps
    end

    add_index :projects, :repo_folder_path, unique: true
  end
end
