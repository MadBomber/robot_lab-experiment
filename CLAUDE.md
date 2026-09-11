# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Rails 8.1 app that runs a four-stage AI coding pipeline (planning → implementation → review → PR) against real git repositories, using `robot_lab`/`robot_lab-rails` to drive LLM agents. It's a Ruby port of a design called "Bottega" — comments throughout the codebase reference that source design and should be read as intentional context, not TODOs.

A `Project` points at a git repo on disk. A `Task` under a project gets its own git worktree and runs through the pipeline one `AgentRun` at a time, with every LLM turn persisted as ordered `Message` rows and broadcast live over Turbo Streams.

Tasks come in two kinds (`Task#task_kind`): **fix** runs the four-stage pipeline; **audit** runs a single read-only `audit` agent that investigates the repo and files GitHub issues via `gh` (started by `AuditTasksController`, never auto-chained).

## Commands

```bash
bin/setup                       # bundle install + db:prepare, idempotent
bin/dev                         # Puma + Tailwind watcher (Procfile.dev)
bin/rails test                  # full test suite (Minitest, parallelized across CPUs)
bin/rails test test/models/task_test.rb            # single file
bin/rails test test/models/task_test.rb:23         # single test at line
bin/rubocop                     # lint (bin/rubocop -a to autocorrect)
bin/ci                          # full local CI: setup, rubocop, bundler-audit, importmap audit, brakeman, tests, seed replant
```

`bin/ci` (via `config/ci.rb`, `ActiveSupport::ContinuousIntegration`) is the authoritative pre-push check. Prefer it over piecing together individual commands when validating a change before commit.

No RSpec — this app uses Minitest with fixtures (`test/fixtures/*.yml`), not factories.

### Gem dependencies

`robot_lab`/`robot_lab-rails` are published gems declared in the plain `Gemfile`. For cross-gem development, `Gemfile.local` (loads `Gemfile` via `eval_gemfile`, then re-declares them as `path:` gems pointing at `../robot_lab` and `../robot_lab-rails` — sibling checkouts in this `robot_lab_project` workspace); the `Gemfile` skips its own copies when `BUNDLE_GEMFILE` is `Gemfile.local`. If a robot_lab API doesn't behave as expected, the fix may belong in the sibling gem, not here. See `../CLAUDE.md` (one level up) for the multi-gem workspace map.

**GitHub Actions CI is intentionally disabled** — the workflow file is committed as `.github/workflows/ci.yml.disabled` (a `.disabled` suffix so Actions won't pick it up), NOT `ci.yml`. Do not re-enable it without explicit instruction; run `bin/ci` locally as the pre-push check.

**json 3.x pin**: `Gemfile` pins `json ~> 3.0`; `config/initializers/active_support_json3_compat.rb` backports `ActiveSupport::JSON.decode` because activesupport 8.1.3.1 still passes JSON.parse a positional options hash. The initializer is version-guarded — delete it once the app moves past Rails 8.1.3.1.

## Architecture: the pipeline state machine

The whole orchestration lives in two small services, deliberately kept separate from each other and from everything else:

- **`AgentRunner`** (`app/services/agent_runner.rb`) — the single entry point that starts an agent run. Guards "one running agent per task" — enforced at the database by the partial unique index `index_agent_runs_one_running_per_task` with `RecordNotUnique` rescued into `AlreadyRunningError` (the in-code check is only a fast path; neither half is redundant) — stamps provider/model on the `Conversation` at creation time (never inferred later), increments `Task#workflow_run_count`, and enqueues `AgentRunJob` only after the transaction commits (Solid Queue is a separate DB; a worker must never see the job before the run row exists). The manual "Run" button (`AgentRunsController#create`), audit kickoff (`AuditTasksController`), and the auto-chaining below all call through this one path.
- **`AgentRunCompletionHandler`** (`app/services/agent_run_completion_handler.rb`) — runs after every `AgentRun` finishes and decides what (if anything) runs next. It reads only `Task` flags (`planning_complete`, `workflow_complete`, `pr_agent_complete`, `blocked_reason`) that agents set via explicit tool calls — **never** parses agent prose/transcript to infer a verdict — and calls `Task#recompute_status!` so the display status stays derived from those same flags. Chains: planning stops (waits for human review) → implementation ↔ review alternate until review sets `workflow_complete` → PR agent runs once → done. Audit runs never chain. Hits `Task::MAX_WORKFLOW_RUNS` (25) and it self-blocks with `blocked_reason: "max_iterations"`.

`AgentRunJob` runs one turn: builds a `RobotLab::Robot` scoped to `task.effective_cwd` (the worktree, or the project checkout if no worktree yet) with a tool set selected by `agent_type` (see `tools_for` in `app/jobs/agent_run_job.rb`), streams output into `TranscriptRecorder`, marks the run completed/failed/cancelled/blocked, then schedules `AgentRunCompletionJob` after a 1-second settle delay to avoid a race with the just-written DB state.

### Plateau detection (two layers)

Both layers block the task with `blocked_reason: "no_progress"` so a human can inspect, guide, and unblock — instead of grinding to the 25-run cap:

- **Within-run**: `PlateauMonitor` (`app/services/plateau_monitor.rb`) watches tool calls/results from `AgentRunJob`'s callbacks and raises `Plateaued` on repeated identical calls (keyed on tool + arguments), repeated identical results in a row, or >200 tool calls in one run. This is the app-level hard stop robot_lab's own DoomLoopDetector (name-only, soft warning) doesn't provide; robot_lab's `max_tool_rounds` is the coarser backstop.
- **Cross-run**: after each completion, the handler records `ProgressFingerprint.for(task)` (checked to-do count + worktree diff/HEAD + review-findings section) via `Task#record_progress!`; if the fingerprint doesn't move for several cycles (`Task#plateaued?`), the impl↔review loop is oscillating and the task blocks.

### Human intervention mid-run

- **Stop/Abandon**: the controller sets `cancel_requested` on the run; `AgentRunJob` reloads the run on every tool call and raises `AgentRunJob::Cancelled`, marking the run `cancelled` (not failed).
- **Guidance/redirect**: `Task#pending_guidance` is consumed by the next run's kickoff message, so human course-corrections apply to exactly one run.

### Prompts

Each agent type's system prompt lives in `app/prompts/{planning,implementation,review,pr,audit}.md` (ERB + YAML front matter, rendered by `robot_lab`'s template system). **The prompts are the actual behavioral spec for each stage** — read them before changing an agent's tool set or the completion-handler's transition logic, since the two must stay in sync (e.g. only the review/pr/planning agents get `mark_*` completion tools; implementation never does — it just stops when done and review runs next automatically; audit gets only read + GitHub-issue tools).

### Adding or changing pipeline behavior

- New agent stage: add a template in `app/prompts/`, a case branch in `AgentRunJob#tools_for`, and a transition in `AgentRunCompletionHandler`.
- Changing when the loop advances/stops: that's `AgentRunCompletionHandler` — it's intentionally the *only* place this logic lives.
- Changing what an agent can do: that's the tool list for its `agent_type` in `AgentRunJob#tools_for`, plus the corresponding tool class in `app/tools/`.

## Tools (`app/tools/`)

All agent-facing tools subclass `RobotLab::Tool` through one of two base classes:

- **`CodingTool`** (`cwd`-scoped: read/write/edit/glob/grep/bash, plus `QualityGateTool` and the GitHub-issue tools) — path resolution confines every filesystem call. Reads honor a per-agent-type **sandbox level** (`tight`/`loose`/`root`, see `CodingTool.agent_type_override`: review gets `root`, pr `tight`, the rest `loose`; env overrides `AGENT_SANDBOX_LEVEL` and `AGENT_READABLE_ROOT`); writes are always cwd-confined at every level.
- **`TaskScopedTool`** (`task`-scoped, not `cwd`-scoped) — the task-doc read/write tools and the `mark_*` completion-signal tools (`TaskCompletionTool` subclasses). These flip `Task` boolean flags directly via ActiveRecord since this port runs in-process (unlike the original design's subprocess-CLI approach — see the comment in `task_completion_tool.rb`).

Stage-specific tools:

- **`QualityGateTool`** (review only) — runs a battery of `bundle exec` quality checks (rubocop, bundler-audit, brakeman, etc.) in the target repo's own bundle and returns a structured pass/fail/skip report; a native port of `asgard quality` so it works on any repo a Project points at.
- **`ListGithubIssuesTool`** / **`CreateGithubIssueTool`** (audit only) — shell out to `gh` from the task's cwd; the audit prompt requires checking existing issues before filing to avoid duplicates.

`BashTool` runs commands via `Open3.popen2e` with a process group and timeout (default 120s); it's the only tool that shells out arbitrarily. `WorktreeService`, `PrStatusService`, and `GithubIssueService` also shell out but always via `Open3` with an argv array — never string interpolation into a shell — when adding new shell-invoking code, follow that pattern.

### MCP servers (review agent only)

Review is the verification stage, so it's the only agent that gets MCP tools. `McpConfigNormalizer` reads a Claude Desktop/Cursor-style config from `config/mcp_servers.json` (override with `MCP_CONFIG_PATH`; ERB interpolation for secrets), normalizes it to the spec array `RobotLab.build(mcp_servers:)` expects, and returns `[]` when the file is absent. RobotLab owns the client lifecycle; `AgentRunJob#teardown` disconnects when the turn ends. A malformed config logs a warning and the review agent runs without MCP tools.

## Services beyond the state machine

- **`TaskCreationService`** — creates a Task plus its filesystem state (worktree + seeded task doc) as one logical unit, cleaning up whatever *was* created when a later step fails. A DB transaction can't do this: rollback never touches the filesystem.
- **`ProjectDestructionService`** — the teardown mirror: DB destroy commits first, then best-effort filesystem cleanup (`CleanupError` is flashed as a notice, not an alert).
- **`GithubIssueService`** / **`PrStatusService`** — best-effort `gh` reads; a missing/unauthenticated `gh` must never break a page ("never load-bearing").

## The task doc

`TaskDocument` (`app/services/task_document.rb`) reads/writes a markdown scratchpad per task at `~/.robot_lab_experiment/projects/<project_id>/tasks/task-<task_id>.md` (root overridable via `ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT`). It deliberately lives **outside** the git worktree so it survives worktree teardown. It's the single shared state agents pass through the pipeline: the planning agent writes `## Original Request` / `## Overview` / `## Implementation Plan` / `## Testing Strategy` / `## To-Do List`; implementation checks off to-do items; review appends/replaces `## Review Findings`. The exact section structure in `app/prompts/planning.md` and `app/prompts/review.md` is a contract other prompts, the UI (`TasksController#show`), and `ProgressFingerprint` depend on — don't change the section names without updating all of them.

## Data model

`Project 1--* Task 1--* Conversation 1--1 AgentRun`, `Conversation 1--* Message`. A `Task` can have many `Conversation`s (one per `AgentRun`) but the UI/handler only ever care about the single currently-`running` one (`Task#running_agent_run`). `Task#status` is display-only state derived from the same flags the handler reads (`Task#derived_status` / `recompute_status!`) — never a second source of truth. `Message#msg_type` enumerates the full transcript vocabulary: `user`, `assistant`, `assistant_thinking`, `tool_use`, `tool_result`, `system`, `result` — `TranscriptRecorder` is the only writer, pairing each `tool_use` with the next `tool_result` (assumes sequential tool execution; see the caveat comment in that file if robot_lab ever turns on concurrent tool calls).

## UI: Poetry component library

All views compose the [Poetry UI](https://poetryui.com) component library (`poetry-core`/`poetry-ui`/`poetry-lucide`/`poetry-agent` gems, default theme) — no hand-rolled Tailwind components or raw hex colors. Rules that bind here:

- Compose with `poetry_*` helpers and Tailwind utilities on Poetry tokens (`bg-card`, `text-muted-foreground`, ...); never write `cn-*` classes or raw colors. Contracts live in `.claude/skills/poetry/` (installed by the generator; regenerate with `bin/rails g poetry:skill`).
- Model-bound forms use `form_with(model:, builder: Poetry::Ui::FormBuilder)` + `f.input`.
- After ANY ERB edit, run `bin/rails poetry:check` — it lints views against the component contracts and must pass clean.
- The tasks/show transcript is a `poetry_message_scroller(id: "transcript")`; `TranscriptRecorder` broadcasts append to its content element (`transcript-messages`), and rows are `poetry_message_scroller_item`s rendered by `messages/_message`. Collapsible rows are native `<details>` (not `poetry_collapsible`) so the "Collapse tool calls" toggle can bulk-drive them.
- App Stimulus controllers live in `app/javascript/controllers/` (`heartbeat`, `llm_options`, `transcript`); Poetry's 53 controllers register in `controllers/index.js` via `registerPoetryControllers`/`registerPoetryAgent`. Note `poetry:toggle:change` fires BEFORE the flip renders — read `event.detail.pressed`, not `aria-pressed`.
- Upgrades: `bundle update` then re-run `bin/rails g poetry:install` (idempotent, theme-sticky) and `bin/rails tailwindcss:build`.

## Config

Default LLM provider/model live as constants in `AgentRunner` (`openrouter` / `moonshotai/kimi-k2.7-code`), overridable per task (`Task#llm_provider`/`llm_model`) or per run. There's no `config/robot_lab.yml` — robot_lab's config cascade falls through to gem defaults + `RubyLLM.configure` in `config/initializers/ruby_llm.rb`, which sets the Ollama base URL (`ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE`, default local) and the OpenRouter key (`OPENROUTER_API_KEY` — RubyLLM does not auto-read it from ENV). `config/initializers/orphan_agent_run_recovery.rb` sweeps any `AgentRun` still `running` to `failed` at boot, scoped only to `rails server`/`bin/jobs` processes (never console/runner/rake/tests) — a server restart mid-turn shouldn't leave a task stuck.

Background jobs run on Solid Queue (`bin/jobs`); no Redis/Sidekiq in this app.
