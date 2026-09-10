# Runs one AgentRun's turn: builds a RobotLab::Robot scoped to the task's
# worktree with the tools appropriate to its agent_type, streams the turn into
# a TranscriptRecorder, marks the run completed/failed, then schedules the
# completion handler after a short settle delay (mirrors Bottega's own
# settle-before-chaining race avoidance -- see AgentRunCompletionHandler).
class AgentRunJob < ApplicationJob
  # Raised to unwind a run that a human asked to Stop/Abandon (see #22). Caught
  # in run_turn, which marks the run cancelled without treating it as a failure.
  class Cancelled < StandardError; end

  queue_as :default

  SETTLE_DELAY = 1.second

  def perform(agent_run_id)
    @agent_run = AgentRun.find(agent_run_id)
    @task = agent_run.task
    @conversation = agent_run.conversation
    @recorder = TranscriptRecorder.new(conversation)
    @cwd = task.effective_cwd
    @sandbox_level = read_sandbox_level_for(agent_run.agent_type)

    run_turn

    AgentRunCompletionJob.set(wait: SETTLE_DELAY).perform_later(agent_run.id)
  end

  private

  # One AgentRun per job execution: perform assigns everything up front and
  # the rest of the job reads it back through these, instead of threading the
  # same run/task/conversation through every private method's parameters.
  attr_reader :agent_run, :task, :conversation, :recorder, :cwd, :sandbox_level, :robot

  def run_turn
    recorder.start
    # Robot#run has its own `tools: :none` default, independent of local_tools
    # passed to RobotLab.build -- without this, the chat's tool list gets
    # wiped to empty on every turn and the LLM never sees any of our tools.
    build_robot.run(kickoff_message, tools: :inherit)
    agent_run.update!(status: "completed")
  rescue Cancelled
    cancelled
  rescue PlateauMonitor::Plateaued, RobotLab::ToolLoopError => e
    plateaued(e)
  rescue StandardError => e
    failed(e)
  ensure
    teardown
  end

  # RobotLab connects the MCP clients when the robot is built; tear down their
  # stdio subprocesses when the turn ends. `try`: build_robot may not have
  # assigned @robot (or returned a robot without MCP) when the turn unwound.
  def teardown
    robot.try(:disconnect)
    recorder.finish
  end

  # A human hit Stop/Abandon; the task is already blocked by the controller.
  def cancelled
    agent_run.update!(status: "cancelled")
    Rails.logger.info("#{tag} cancelled by request")
  end

  # A stuck run, caught early by the within-run monitor (or robot_lab's own
  # circuit breaker). Block the whole task so the pipeline stops instead of
  # burning more runs; a human can inspect, guide, and unblock (see #22/#23).
  def plateaued(error)
    agent_run.update!(status: "blocked")
    task.update!(
      blocked_reason: "no_progress",
      blocked_detail: "No progress: #{plateau_reason(error)} during run ##{agent_run.id} (#{agent_run.agent_type})",
      blocked_run_id: agent_run.id
    )
    Rails.logger.warn("#{tag} plateaued: #{error.message}")
  end

  # PlateauMonitor::Plateaued#reason is the clean, prefix-free message; any
  # other error class (e.g. robot_lab's own circuit breaker) falls back to
  # #message, which every StandardError has.
  def plateau_reason(error)
    error.try(:reason) || error.message
  end

  def failed(error)
    agent_run.update!(status: "failed")
    Rails.logger.error("#{tag} failed: #{error.inspect}")
  end

  def tag
    "AgentRunJob##{agent_run.id} (#{agent_run.agent_type})"
  end

  # The opening message for the turn. Prepends any human redirect (#23) queued
  # since the last run and consumes it, so guidance applies to exactly this run.
  def kickoff_message
    guidance = task.pending_guidance
    return "Begin." if guidance.blank?

    task.update!(pending_guidance: nil)
    "A human overseeing this task has provided the following guidance. " \
      "Follow it, adjusting your plan as needed:\n\n#{guidance}\n\nBegin."
  end

  # Builds the turn's robot and keeps it on @robot so teardown can reach it
  # even when the turn unwinds mid-flight.
  def build_robot
    monitor = PlateauMonitor.new
    @robot = RobotLab.build(
      name: "#{agent_run.agent_type}-task-#{task.id}",
      template: agent_run.agent_type.to_sym,
      context: template_context,
      provider: conversation.provider,
      model: conversation.model,
      local_tools: tools_for,
      mcp_servers: mcp_servers, # RobotLab connects them + injects their tools
      max_tool_rounds: PlateauMonitor::MAX_TOOL_CALLS, # robot_lab's coarse circuit-breaker backstop
      on_content: ->(chunk) { recorder.record_content(chunk) },
      on_tool_call: lambda { |tool_call|
        recorder.record_tool_call(tool_call)
        # Cooperative Stop/Abandon: a reload each tool call is a cheap way to see
        # a cancel that was requested after this job started (see #22).
        raise Cancelled if agent_run.reload.cancel_requested?

        monitor.record_tool_call(tool_call)
      },
      on_tool_result: lambda { |result|
        recorder.record_tool_result(result)
        monitor.record_tool_result(result)
      }
    )
  end

  def template_context
    context = { task_doc_path: TaskDocument.doc_path(task), task_id: task.id }
    context[:pr_status] = PrStatusService.call(task) if agent_run.pr?
    context
  end

  def tools_for
    doc_tools = [ReadTaskDocTool.new(task:), WriteTaskDocTool.new(task:)]

    case agent_run.agent_type
    when "planning" then doc_tools + planning_tools
    when "implementation" then doc_tools + implementation_tools
    when "review" then doc_tools + review_tools
    when "pr" then doc_tools + pr_tools
    when "audit" then doc_tools + audit_tools
    end
  end

  def read_sandbox_level_for(agent_type)
    CodingTool.effective_sandbox_level(agent_type: agent_type)
  end

  def planning_tools
    # RobotLab::AskUser reads from $stdin/$stdout, which has no meaningful
    # source in a background job -- it would hang the run. Clarifying
    # questions over the web UI are a later phase (extra/chat-ux.md); for now
    # the prompt instructs the agent to make a reasonable assumption instead.
    [ReadFileTool.new(cwd:, sandbox_level:), GlobTool.new(cwd:, sandbox_level:), GrepTool.new(cwd:, sandbox_level:),
     MarkPlanningCompleteTool.new(task:)]
  end

  def implementation_tools
    [ReadFileTool.new(cwd:, sandbox_level:),
     WriteFileTool.new(cwd:, sandbox_level: "tight"), EditFileTool.new(cwd:, sandbox_level: "tight"),
     GlobTool.new(cwd:, sandbox_level:), GrepTool.new(cwd:, sandbox_level:), BashTool.new(cwd:)]
  end

  def review_tools
    [ReadFileTool.new(cwd:, sandbox_level:), GlobTool.new(cwd:, sandbox_level:),
     GrepTool.new(cwd:, sandbox_level:), BashTool.new(cwd:), QualityGateTool.new(cwd:),
     MarkWorkflowCompleteTool.new(task:), MarkWorkflowBlockedTool.new(task:)]
  end

  def pr_tools
    [BashTool.new(cwd:), MarkPrCompleteTool.new(task:)]
  end

  def audit_tools
    [ReadFileTool.new(cwd:, sandbox_level:), GlobTool.new(cwd:, sandbox_level:), GrepTool.new(cwd:, sandbox_level:),
     ListGithubIssuesTool.new(cwd:), CreateGithubIssueTool.new(cwd:)]
  end

  # MCP servers for this run. Review is the verification stage, so it's the one
  # that gets browser/MCP access; other stages get none. RobotLab owns the
  # connection lifecycle (Robot::MCPManagement) -- we just hand it the spec array.
  def mcp_servers
    return [] unless agent_run.agent_type == "review"

    McpConfigNormalizer.call
  rescue McpConfigNormalizer::Error => e
    Rails.logger.warn("MCP config invalid, review agent running without MCP tools: #{e.message}")
    []
  end
end
