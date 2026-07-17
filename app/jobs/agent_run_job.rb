# Runs one AgentRun's turn: builds a RobotLab::Robot scoped to the task's
# worktree with the tools appropriate to its agent_type, streams the turn into
# a TranscriptRecorder, marks the run completed/failed, then schedules the
# completion handler after a short settle delay (mirrors Bottega's own
# settle-before-chaining race avoidance -- see AgentRunCompletionHandler).
class AgentRunJob < ApplicationJob
  queue_as :default

  SETTLE_DELAY = 1.second

  def perform(agent_run_id)
    agent_run = AgentRun.find(agent_run_id)
    task = agent_run.task
    conversation = agent_run.conversation
    recorder = TranscriptRecorder.new(conversation)

    run_turn(agent_run, task, conversation, recorder)

    AgentRunCompletionJob.set(wait: SETTLE_DELAY).perform_later(agent_run.id)
  end

  private

  def run_turn(agent_run, task, conversation, recorder)
    recorder.start
    robot = build_robot(agent_run, task, conversation, recorder)
    # Robot#run has its own `tools: :none` default, independent of local_tools
    # passed to RobotLab.build -- without this, the chat's tool list gets
    # wiped to empty on every turn and the LLM never sees any of our tools.
    robot.run("Begin.", tools: :inherit)
    agent_run.update!(status: "completed")
  rescue StandardError => e
    agent_run.update!(status: "failed")
    Rails.logger.error("AgentRunJob##{agent_run.id} (#{agent_run.agent_type}) failed: #{e.class}: #{e.message}")
  ensure
    # RobotLab connects the MCP clients when the robot is built; tear down their
    # stdio subprocesses when the turn ends.
    robot.disconnect if robot.respond_to?(:disconnect)
    recorder.finish
  end

  def build_robot(agent_run, task, conversation, recorder)
    RobotLab.build(
      name: "#{agent_run.agent_type}-task-#{task.id}",
      template: agent_run.agent_type.to_sym,
      context: template_context(agent_run, task),
      provider: conversation.provider,
      model: conversation.model,
      local_tools: tools_for(agent_run, task),
      mcp_servers: mcp_servers_for(agent_run), # RobotLab connects them + injects their tools
      on_content: ->(chunk) { recorder.record_content(chunk) },
      on_tool_call: ->(tool_call) { recorder.record_tool_call(tool_call) },
      on_tool_result: ->(result) { recorder.record_tool_result(result) }
    )
  end

  def template_context(agent_run, task)
    context = { task_doc_path: TaskDocument.doc_path(task), task_id: task.id }
    context[:pr_status] = PrStatusService.call(task) if agent_run.pr?
    context
  end

  def tools_for(agent_run, task)
    doc_tools = [ReadTaskDocTool.new(task:), WriteTaskDocTool.new(task:)]
    cwd = task.effective_cwd

    case agent_run.agent_type
    when "planning" then doc_tools + planning_tools(cwd, task)
    when "implementation" then doc_tools + implementation_tools(cwd)
    when "review" then doc_tools + review_tools(cwd, task)
    when "pr" then doc_tools + pr_tools(cwd, task)
    when "audit" then doc_tools + audit_tools(cwd)
    end
  end

  def planning_tools(cwd, task)
    # RobotLab::AskUser reads from $stdin/$stdout, which has no meaningful
    # source in a background job -- it would hang the run. Clarifying
    # questions over the web UI are a later phase (extra/chat-ux.md); for now
    # the prompt instructs the agent to make a reasonable assumption instead.
    [ReadFileTool.new(cwd:), GlobTool.new(cwd:), GrepTool.new(cwd:), MarkPlanningCompleteTool.new(task:)]
  end

  def implementation_tools(cwd)
    [ReadFileTool.new(cwd:), WriteFileTool.new(cwd:), EditFileTool.new(cwd:),
     GlobTool.new(cwd:), GrepTool.new(cwd:), BashTool.new(cwd:)]
  end

  def review_tools(cwd, task)
    [ReadFileTool.new(cwd:), GlobTool.new(cwd:), GrepTool.new(cwd:), BashTool.new(cwd:),
     MarkWorkflowCompleteTool.new(task:), MarkWorkflowBlockedTool.new(task:)]
  end

  def pr_tools(cwd, task)
    [BashTool.new(cwd:), MarkPrCompleteTool.new(task:)]
  end

  def audit_tools(cwd)
    [ReadFileTool.new(cwd:), GlobTool.new(cwd:), GrepTool.new(cwd:),
     ListGithubIssuesTool.new(cwd:), CreateGithubIssueTool.new(cwd:)]
  end

  # MCP servers for this run. Review is the verification stage, so it's the one
  # that gets browser/MCP access; other stages get none. RobotLab owns the
  # connection lifecycle (Robot::MCPManagement) -- we just hand it the spec array.
  def mcp_servers_for(agent_run)
    return [] unless agent_run.agent_type == "review"

    McpConfigNormalizer.call
  rescue McpConfigNormalizer::Error => e
    Rails.logger.warn("MCP config invalid, review agent running without MCP tools: #{e.message}")
    []
  end
end
