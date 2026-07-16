# The entire state machine, in one place, deciding what (if anything) runs
# next after an AgentRun finishes. Reads only Task flags -- never agent
# transcript/prose -- and re-reads the Task fresh so it never trusts a
# possibly-stale in-memory copy. See core/orchestration-loop.md notes in
# shimmying-floating-island.md for the source design this mirrors.
class AgentRunCompletionHandler
  Result = Data.define(:action, :next_agent_run)

  def self.call(agent_run)
    new(agent_run).call
  end

  def initialize(agent_run)
    @agent_run = agent_run
    @task = agent_run.task.reload
  end

  def call
    return no_chain(:failed_no_chain) if @agent_run.failed?
    return no_chain(:stopped_after_planning) if @agent_run.planning?

    if @task.workflow_complete?
      return no_chain(:already_complete) if @task.pr_agent_complete?

      return start(:pr, :started_pr)
    end

    return no_chain(:stopped_blocked) if @task.blocked?

    if @task.iteration_cap_reached?
      @task.update!(blocked_reason: "max_iterations")
      return no_chain(:blocked_max_iterations)
    end

    next_type = @agent_run.implementation? ? :review : :implementation
    start(next_type, next_type == :review ? :chained_to_review : :chained_to_implementation)
  end

  private

  def start(agent_type, action)
    run = AgentRunner.start_agent_run(@task, agent_type)
    Result.new(action:, next_agent_run: run)
  rescue AgentRunner::AlreadyRunningError
    no_chain(:already_running)
  end

  def no_chain(action)
    Result.new(action:, next_agent_run: nil)
  end
end
