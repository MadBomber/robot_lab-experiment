# Runs one AgentRun's turn: builds a RobotLab::Robot scoped to the task's
# worktree with the tools appropriate to its agent_type (see AgentToolset), streams the turn into
# a TranscriptRecorder, marks the run completed/failed, then schedules the
# completion handler after a short settle delay (mirrors Bottega's own
# settle-before-chaining race avoidance -- see AgentRunCompletionHandler).
class AgentRunJob < ApplicationJob
  # Raised to unwind a run that a human asked to Stop/Abandon (see #22). Caught
  # in run_turn, which marks the run cancelled without treating it as a failure.
  class Cancelled < StandardError; end

  queue_as :default

  SETTLE_DELAY = 1.second

  CLAUDE_CODE = "claude_code".freeze
  # Seconds before a claude_code stage is killed. The provider's own default
  # (600) is too short for an implementation stage on a real repo.
  CLAUDE_CODE_TIMEOUT = 1800
  # Appended to each stage's system prompt for claude_code runs: the stage
  # prompts name the app's tools bare, but Claude Code sees MCP tools under
  # a server prefix.
  CLAUDE_CODE_NOTE = <<~NOTE.freeze
    You are running inside Claude Code. The task tools these instructions name
    (read_task_doc, write_task_doc, the mark_* tools, quality_gate,
    list_github_issues, create_github_issue) are on the "#{AgentToolset::MCP_SERVER}" MCP server:
    call them as mcp__#{AgentToolset::MCP_SERVER}__<name>, for example
    mcp__#{AgentToolset::MCP_SERVER}__read_task_doc. For reading, searching, editing and
    running commands, use your built-in tools.
  NOTE

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
    build_robot.run(kickoff_message, **run_selection)
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

  # Robot#run has its own `tools: :none` / `mcp: :none` defaults, independent
  # of what was passed to RobotLab.build -- without :inherit, the chat's tool
  # list gets wiped to empty on every turn and the LLM never sees any of our
  # tools, and the build-time MCP servers are never selected for the run.
  # Claude Code is the exception: it takes no RubyLLM tools at all (the
  # provider raises if any are attached) and gets the app's tools over MCP
  # instead, from bin/task_mcp.
  def run_selection
    claude_code? ? { tools: :none, mcp: :none } : { tools: :inherit, mcp: :inherit }
  end

  def claude_code?
    conversation.provider == CLAUDE_CODE
  end

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
      **tool_kwargs,
      max_tool_rounds: PlateauMonitor::MAX_TOOL_CALLS, # robot_lab's coarse circuit-breaker backstop
      on_content: ->(chunk) { recorder.record_content(chunk) },
      on_tool_call: lambda { |tool_call|
        recorder.record_tool_call(tool_call)
        # Cooperative Stop/Abandon: a reload each tool call is a cheap way to see
        # a cancel that was requested after this job started (see #22).
        raise Cancelled if cancel_requested?

        monitor.record_tool_call(tool_call)
      },
      on_tool_result: lambda { |result|
        recorder.record_tool_result(result)
        monitor.record_tool_result(result)
      }
    )
    configure_claude_code(monitor) if claude_code?
    @robot
  end

  def cancel_requested?
    agent_run.reload.cancel_requested?
  end

  # What the robot is built with: the app's tool objects (and, for review,
  # MCP servers) -- or for Claude Code none at all, plus a note on how the
  # app's tools are named over MCP.
  def tool_kwargs
    return { local_tools: [], mcp: [], system_prompt: CLAUDE_CODE_NOTE } if claude_code?

    { local_tools: toolset.ruby_llm_tools,
      mcp: mcp_servers } # RobotLab registers them; the run attaches their tools
  end

  def toolset
    @toolset ||= AgentToolset.new(agent_run:, task:, cwd:, sandbox_level:)
  end

  # The claude CLI's settings for this run. with_provider_options replaces
  # whatever the chat carries, so merge onto it. Claude Code's tool events
  # come back through on_event, which keeps the transcript, Stop/Abandon and
  # the PlateauMonitor working (see ClaudeCodeEventBridge).
  def configure_claude_code(monitor)
    bridge = ClaudeCodeEventBridge.new(recorder:, monitor:, cancel_requested: -> { cancel_requested? })
    current = robot.chat.provider_options.to_h
    robot.with_provider_options(current.merge(claude_code: claude_code_options(bridge)))
  end

  def claude_code_options(bridge)
    { cwd:, timeout: CLAUDE_CODE_TIMEOUT, permission_mode: toolset.claude_code_permission_mode,
      args: claude_code_args, on_event: bridge }
  end

  # --tools limits which built-ins exist for the run, --allowedTools
  # pre-approves them (batch mode refuses anything it would have asked
  # about), and --strict-mcp-config with the one task server keeps the
  # user's own MCP servers out. --setting-sources leaves out the user's
  # personal settings -- their hooks, plugins and CLAUDE.md instructions
  # belong to their interactive sessions, not to pipeline stages.
  def claude_code_args
    ["--tools", toolset.claude_code_builtins.join(","),
     "--allowedTools", toolset.claude_code_allowed_tools.join(","),
     "--mcp-config", JSON.generate(mcpServers: { AgentToolset::MCP_SERVER => task_mcp_server }),
     "--strict-mcp-config",
     "--setting-sources", "project,local"]
  end

  # bin/task_mcp, launched by Claude Code from the task's worktree: an
  # absolute command, and a BUNDLE_GEMFILE that doesn't depend on that cwd.
  def task_mcp_server
    { command: Rails.root.join("bin/task_mcp").to_s,
      args: [agent_run.id.to_s],
      env: { "BUNDLE_GEMFILE" => File.expand_path(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"), Rails.root),
             "RAILS_ENV" => Rails.env } }
  end

  def template_context
    context = { task_doc_path: TaskDocument.doc_path(task), task_id: task.id }
    context[:pr_status] = PrStatusService.call(task) if agent_run.pr?
    context
  end

  def read_sandbox_level_for(agent_type)
    CodingTool.effective_sandbox_level(agent_type: agent_type)
  end

  # MCP servers for this run. Review is the verification stage, so it's the one
  # that gets browser/MCP access; other stages get none. RobotLab owns the
  # connection lifecycle (its per-robot MCP::Registry) -- we just hand it the spec array.
  def mcp_servers
    return [] unless agent_run.agent_type == "review"

    McpConfigNormalizer.call
  rescue McpConfigNormalizer::Error => e
    Rails.logger.warn("MCP config invalid, review agent running without MCP tools: #{e.message}")
    []
  end
end
