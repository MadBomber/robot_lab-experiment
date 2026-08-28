# Starts one agent run for a task: guards the one-running-agent-per-task rule,
# stamps the conversation's provider/model explicitly (never inferred later),
# increments the iteration counter, and enqueues the job that actually drives
# the Robot. This is the single entry point for both the manual "Run" button
# and AgentRunCompletionHandler's auto-chaining -- there is no separate code
# path for the two, matching Bottega's own `startAgentRun` design.
class AgentRunner
  class AlreadyRunningError < StandardError; end

  # Fallback when the task's project has no llm_provider/llm_model of its own
  # (see Project.llm_options). OpenRouter-hosted model; requires
  # OPENROUTER_API_KEY -- see config/initializers/ruby_llm.rb.
  DEFAULT_PROVIDER = "openrouter".freeze
  DEFAULT_MODEL = "moonshotai/kimi-k2.7-code".freeze

  def self.start_agent_run(task, agent_type, provider: nil, model: nil)
    new(task).start_agent_run(agent_type, provider:, model:)
  end

  def initialize(task)
    @task = task
  end

  def start_agent_run(agent_type, provider: nil, model: nil)
    raise AlreadyRunningError, "task #{@task.id} already has a running agent" if @task.running_agent_run

    @task.increment!(:workflow_run_count)

    conversation = Conversation.create!(
      task: @task, provider: provider || effective_provider, model: model || effective_model, started_at: Time.current
    )
    agent_run = AgentRun.create!(
      task: @task, conversation:, agent_type: agent_type.to_s, status: "running"
    )
    @task.recompute_status!

    AgentRunJob.perform_later(agent_run.id)
    agent_run
  end

  private

  def effective_provider
    @task.llm_provider.presence || DEFAULT_PROVIDER
  end

  def effective_model
    @task.llm_model.presence || DEFAULT_MODEL
  end
end
