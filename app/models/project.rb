class Project < ApplicationRecord
  has_many :tasks, dependent: :destroy

  validates :name, presence: true
  validates :repo_folder_path, presence: true, uniqueness: true
  validates :llm_model, presence: true, if: :llm_provider?
  validates :llm_provider, presence: true, if: :llm_model?
  validate :repo_folder_path_must_be_a_git_repo
  validate :repo_folder_path_must_not_be_a_managed_worktree

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
    # A linked worktree's .git is a plain file where a normal checkout has a
    # directory; File.exist? admits both while still rejecting bare repos,
    # .git dirs themselves, and subdirectories of a checkout.
    return if File.exist?(File.join(repo_folder_path, ".git"))

    errors.add(:repo_folder_path, "is not a git repository")
  end

  # WorktreeService materializes each task's worktree under a container
  # derived from its project's path ("<repo>-worktrees/") and tears those
  # down with `git worktree remove --force` during task/project cleanup. A
  # second Project rooted inside such a container would lose its entire
  # checkout to the owning project's teardown, so those paths never validate.
  def repo_folder_path_must_not_be_a_managed_worktree
    return if repo_folder_path.blank?

    Pathname.new(repo_folder_path).ascend do |dir|
      next unless dir.to_s.end_with?("-worktrees")
      next unless File.exist?(File.join(dir.to_s.delete_suffix("-worktrees"), ".git"))

      errors.add(:repo_folder_path, "is a task worktree managed by another project")
      break
    end
  end
end
