# Starts one agent run for a task: guards the one-running-agent-per-task rule,
# stamps the conversation's provider/model explicitly (never inferred later),
# increments the iteration counter, and enqueues the job that actually drives
# the Robot. This is the single entry point for both the manual "Run" button
# and AgentRunCompletionHandler's auto-chaining -- there is no separate code
# path for the two, matching Bottega's own `startAgentRun` design.
class AgentRunner
  class AlreadyRunningError < StandardError; end

  # Local Ollama server, no API key required. See config/robot_lab.yml for the
  # ollama_api_base default (overridable via ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE).
  DEFAULT_PROVIDER = "ollama".freeze
  DEFAULT_MODEL = "qwen3.6:latest".freeze

  def self.start_agent_run(task, agent_type, provider: DEFAULT_PROVIDER, model: DEFAULT_MODEL)
    new(task).start_agent_run(agent_type, provider:, model:)
  end

  def initialize(task)
    @task = task
  end

  def start_agent_run(agent_type, provider: DEFAULT_PROVIDER, model: DEFAULT_MODEL)
    raise AlreadyRunningError, "task #{@task.id} already has a running agent" if @task.running_agent_run

    @task.increment!(:workflow_run_count)
    @task.update!(status: "in_progress") if @task.pending?

    conversation = Conversation.create!(
      task: @task, provider:, model:, started_at: Time.current
    )
    agent_run = AgentRun.create!(
      task: @task, conversation:, agent_type: agent_type.to_s, status: "running"
    )

    AgentRunJob.perform_later(agent_run.id)
    agent_run
  end
end
