class AddLlmProviderAndModelToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :llm_provider, :string
    add_column :projects, :llm_model, :string
  end
end
