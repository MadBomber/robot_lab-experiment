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

  # Local model servers offered in the picker, in display order: LM Studio
  # and Apple's on-device model via apfel (providers registered by the gems
  # in the Gemfile; see config/initializers/ruby_llm.rb for their addresses).
  LOCAL_PROVIDERS = %w[lms apfel].freeze

  # Real provider/model pairs for the LLM picker on the projects index page,
  # scoped to the providers this app can actually reach. OpenRouter comes
  # from RubyLLM's own bundled model registry -- no network call, and no
  # guessing at model names. Local servers have no such registry (their
  # models are whatever is installed there), so each is a live query against
  # its server, tolerant of it not running.
  def self.llm_options
    LOCAL_PROVIDERS.flat_map { |slug| local_options(slug) } + claude_code_options + openrouter_options
  end

  # Claude Code (`claude -p`, via the claude_code provider gem) brings its
  # own tools and gets the app's over MCP (see AgentRunJob), so it doesn't
  # report function_calling and never goes through pipeline_capable?. Its
  # catalog is static -- the CLI's model aliases -- so this makes no call.
  def self.claude_code_options
    provider = RubyLLM::Provider.providers.fetch(:claude_code).new(RubyLLM.config)
    provider.list_models.map { |m| { provider: "claude_code", model: m.id, label: "Claude Code - #{m.id}" } }
  rescue StandardError
    []
  end
  private_class_method :claude_code_options

  def self.openrouter_options
    RubyLLM.models.chat_models.by_provider("openrouter").all.sort_by(&:id).map do |m|
      { provider: "openrouter", model: m.id, label: m.label }
    end
  end
  private_class_method :openrouter_options

  # The models a local provider's server reports that can drive a pipeline
  # agent, or [] when the server is down or the provider isn't registered.
  def self.local_options(slug)
    models = RubyLLM::Provider.providers.fetch(slug.to_sym).new(local_probe_config).list_models
    models.select { |m| pipeline_capable?(m) }.map { |m| { provider: slug, model: m.id, label: m.label } }
  rescue StandardError
    []
  end
  private_class_method :local_options

  # Seconds a local server gets to answer the picker's model query.
  LOCAL_PROBE_TIMEOUT = 2

  # The config the picker's local-server queries run under: a copy of the
  # app's RubyLLM config with no retries and a short timeout. A server that
  # isn't running refuses the connection instantly, but RubyLLM's default
  # retries (3, with backoff) turn each refusal into ~8s -- and the projects
  # page renders the picker on every load. Agent runs keep the real config.
  def self.local_probe_config
    RubyLLM.config.dup.tap do |config|
      config.max_retries = 0
      config.request_timeout = LOCAL_PROBE_TIMEOUT
    end
  end

  # Every agent stage works through tool calls, so a model must be a chat
  # model that can call functions. A server that reports no capabilities at
  # all (apfel) is given the benefit of the doubt; one that reports them
  # without function_calling (most small LM Studio models) is left out, as
  # are embedding models.
  def self.pipeline_capable?(model)
    return false unless model.type.to_s == "chat"

    model.capabilities.empty? || model.capabilities.map(&:to_s).include?("function_calling")
  end
  private_class_method :pipeline_capable?

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
