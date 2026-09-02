architecture :rails,
             components: {
               controllers: "app/controllers/**/*.rb",
               models: "app/models/**/*.rb",
               helpers: "app/helpers/**/*.rb",
               mailers: "app/mailers/**/*.rb",
               jobs: { in: "app/jobs/**/*.rb", except: "app/jobs/agent_run_job.rb" },
               services: { in: "app/services/**/*.rb", except: "app/services/agent_runner.rb" }
             }

# The `app/tools/` directory is RobotLab-specific: agent-facing tools the
# pipeline hands to a Robot. It isn't part of stock Rails MVC, so it needs its
# own boundary -- tools run inside an LLM turn and must never reach into the
# request/response cycle.
component :tools, in: "app/tools/**/*.rb"
tools.cannot_use :controllers,
                 because: "tools run inside an LLM turn (AgentRunJob), never inside a request -- see app/tools/coding_tool.rb"
tools.cannot_call :render, :redirect_to, :params, :session, :cookies, :flash,
                  receiver: :none,
                  because: "tools have no request context to draw these from"

# CodingTool subclasses are filesystem tools confined to task.effective_cwd
# (see CodingTool#resolve_path); TaskScopedTool subclasses (task-doc I/O and
# the mark_* completion signals) are scoped to the Task record instead, not
# the checkout. They're deliberately separate hierarchies -- see the "Tools"
# section of CLAUDE.md.
component :coding_tools, descendants_of: "CodingTool"
component :task_scoped_tools, descendants_of: "TaskScopedTool"
coding_tools.cannot_use :task_scoped_tools,
                        because: "a cwd-scoped filesystem tool has no business touching Task-scoped state directly"

# AgentRunner is documented as the single entry point that starts an agent
# run -- the manual "Run" button and AgentRunCompletionHandler's auto-chaining
# both go through it, and only it enqueues AgentRunJob. Keep that true.
component :agent_runner, in: "app/services/agent_runner.rb"
component :agent_run_job, in: "app/jobs/agent_run_job.rb"
agent_run_job.can_only_be_used_by :agent_runner,
                                  because: "AgentRunner is the only path that may enqueue a run " \
                                           "-- see CLAUDE.md 'Architecture: the pipeline state machine'"
# Excluding agent_runner.rb from the plain :services glob (above) keeps the
# can_only_be_used_by check honest, but controllers legitimately call
# AgentRunner directly (the manual "Run" button) -- restore that one path.
controllers.can_only_use :agent_runner

# AgentRunCompletionHandler decides what runs next from Task boolean flags
# only (planning_complete, workflow_complete, pr_agent_complete,
# blocked_reason) that agents set via explicit mark_* tool calls. It must
# never infer a verdict by parsing agent prose or the message transcript.
component :agent_run_completion_handler, in: "app/services/agent_run_completion_handler.rb"
agent_run_completion_handler.cannot_reference_constants "Message",
                                                        because: "reads only Task flags set via mark_* tool calls, " \
                                                                 "never the transcript -- see CLAUDE.md"
