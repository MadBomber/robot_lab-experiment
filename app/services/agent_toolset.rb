# Which tools one agent run gets, for both ways a run can be driven:
#
# - #ruby_llm_tools: the app's own tool objects, handed to RobotLab.build for
#   every provider that takes RubyLLM tools (lms, apfel, openrouter, ...).
# - #bridge_tools / #claude_code_*: for the claude_code provider, which runs
#   `claude -p` with its own built-in tools and cannot take RubyLLM tools.
#   The built-ins cover file reading, editing, search and the shell; the
#   app-specific tools (task doc, completion flags, quality gate, GitHub
#   issues) reach it over MCP from bin/task_mcp, which serves #bridge_tools.
#
# AgentRunJob and bin/task_mcp both build their lists here, so the two paths
# can't drift apart.
class AgentToolset
  # The server name in Claude Code's --mcp-config; its tools appear to the
  # agent as mcp__task__<tool name>.
  MCP_SERVER = "task".freeze

  # Built-ins each stage may use, mirroring #ruby_llm_tools. Edit/Write appear
  # only for implementation, which runs under acceptEdits so they are approved
  # inside the worktree and refused outside it (the "tight" write sandbox).
  CLAUDE_CODE_BUILTINS = {
    "planning" => %w[Read Glob Grep],
    "implementation" => %w[Read Edit Write Glob Grep Bash],
    "review" => %w[Read Glob Grep Bash],
    "pr" => %w[Bash],
    "audit" => %w[Read Glob Grep]
  }.freeze

  # Built-ins pre-approved with --allowedTools; any other action the agent
  # attempts is refused, because batch mode can't ask.
  CLAUDE_CODE_PREAPPROVED = %w[Read Glob Grep Bash].freeze

  attr_reader :agent_run, :task, :cwd, :sandbox_level

  def initialize(agent_run:, task: agent_run.task, cwd: task.effective_cwd,
                 sandbox_level: CodingTool.effective_sandbox_level(agent_type: agent_run.agent_type))
    @agent_run = agent_run
    @task = task
    @cwd = cwd
    @sandbox_level = sandbox_level
  end

  def agent_type
    agent_run.agent_type
  end

  def ruby_llm_tools
    doc_tools + stage_tools
  end

  # The app tools Claude Code has no built-in equivalent for.
  def bridge_tools
    doc_tools + stage_tools.select { |tool| bridged?(tool) }
  end

  # Value for `claude --tools`: the only built-ins that exist for the run.
  def claude_code_builtins
    CLAUDE_CODE_BUILTINS.fetch(agent_type)
  end

  # Value for `claude --allowedTools`: this stage's pre-approved built-ins
  # plus every tool on the task MCP server.
  def claude_code_allowed_tools
    (claude_code_builtins & CLAUDE_CODE_PREAPPROVED) + ["mcp__#{MCP_SERVER}"]
  end

  # Value for `claude --permission-mode`, or nil for the CLI default.
  def claude_code_permission_mode
    "acceptEdits" if claude_code_builtins.include?("Edit")
  end

  private

  # Task-bound tools always cross the bridge. Of the cwd-bound coding tools,
  # only those with no Claude Code built-in counterpart do.
  def bridged?(tool)
    tool.is_a?(TaskScopedTool) ||
      [QualityGateTool, ListGithubIssuesTool, CreateGithubIssueTool].any? { |klass| tool.is_a?(klass) }
  end

  def doc_tools
    [ReadTaskDocTool.new(task:), WriteTaskDocTool.new(task:)]
  end

  def stage_tools
    case agent_type
    when "planning" then planning_tools
    when "implementation" then implementation_tools
    when "review" then review_tools
    when "pr" then pr_tools
    when "audit" then audit_tools
    end
  end

  def planning_tools
    # RobotLab::AskUser reads from $stdin/$stdout, which has no meaningful
    # source in a background job -- it would hang the run. Clarifying
    # questions over the web UI are a later phase (extra/chat-ux.md); for now
    # the prompt instructs the agent to make a reasonable assumption instead.
    [*read_tools, MarkPlanningCompleteTool.new(task:)]
  end

  def implementation_tools
    [ReadFileTool.new(cwd:, sandbox_level:),
     WriteFileTool.new(cwd:, sandbox_level: "tight"), EditFileTool.new(cwd:, sandbox_level: "tight"),
     GlobTool.new(cwd:, sandbox_level:), GrepTool.new(cwd:, sandbox_level:), BashTool.new(cwd:)]
  end

  def review_tools
    [*read_tools, BashTool.new(cwd:), QualityGateTool.new(cwd:),
     MarkWorkflowCompleteTool.new(task:), MarkWorkflowBlockedTool.new(task:)]
  end

  def pr_tools
    [BashTool.new(cwd:), MarkPrCompleteTool.new(task:)]
  end

  def audit_tools
    [*read_tools, ListGithubIssuesTool.new(cwd:), CreateGithubIssueTool.new(cwd:)]
  end

  def read_tools
    [ReadFileTool.new(cwd:, sandbox_level:), GlobTool.new(cwd:, sandbox_level:), GrepTool.new(cwd:, sandbox_level:)]
  end
end
