class Project < ApplicationRecord
  has_many :tasks, dependent: :destroy

  validates :name, presence: true
  validates :repo_folder_path, presence: true, uniqueness: true
  validates :llm_model, presence: true, if: :llm_provider?
  validates :llm_provider, presence: true, if: :llm_model?
  validate :repo_folder_path_must_be_a_git_repo

  def effective_cwd
    subproject_path.present? ? File.join(repo_folder_path, subproject_path) : repo_folder_path
  end

  # Real provider/model pairs for the LLM picker on the projects index page,
  # scoped to the two providers this app actually has credentials for (see
  # config/initializers/ruby_llm.rb). OpenRouter comes from RubyLLM's own
  # bundled model registry -- no network call, and no guessing at model names.
  # Ollama has no such registry (its models are whatever's pulled locally), so
  # that half is a live query against the configured Ollama server, tolerant
  # of it being unreachable.
  def self.llm_options
    ollama_options + openrouter_options
  end

  def self.openrouter_options
    RubyLLM.models.chat_models.by_provider("openrouter").all.sort_by(&:id).map do |m|
      { provider: "openrouter", model: m.id, label: m.label }
    end
  end
  private_class_method :openrouter_options

  def self.ollama_options
    RubyLLM::Provider.providers[:ollama].new(RubyLLM.config).list_models.map do |m|
      { provider: "ollama", model: m.id, label: m.label }
    end
  rescue StandardError
    []
  end
  private_class_method :ollama_options

  private

  def repo_folder_path_must_be_a_git_repo
    return if repo_folder_path.blank?
    return if Dir.exist?(File.join(repo_folder_path, ".git"))

    errors.add(:repo_folder_path, "is not a git repository")
  end
end
