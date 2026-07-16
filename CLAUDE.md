# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Rails 8.1 app that runs a four-stage AI coding pipeline (planning → implementation → review → PR) against real git repositories, using `robot_lab`/`robot_lab-rails` (local sibling gems, see `Gemfile.local`) to drive LLM agents. It's a Ruby port of a design called "Bottega" — comments throughout the codebase reference that source design and should be read as intentional context, not TODOs.

A `Project` points at a git repo on disk. A `Task` under a project gets its own git worktree and runs through the pipeline one `AgentRun` at a time, with every LLM turn persisted as ordered `Message` rows and broadcast live over Turbo Streams.

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

`bin/ci` (via `config/ci.rb`, `ActiveSupport::ContinuousIntegration`) is the authoritative pre-push check — it's what CI runs. Prefer it over piecing together individual commands when validating a change before commit.

No RSpec — this app uses Minitest with fixtures (`test/fixtures/*.yml`), not factories.

### Gem dependencies

`Gemfile.local` (loaded via `eval_gemfile "Gemfile"`, actually used by `bundle install`/`bin/*`) points `robot_lab` and `robot_lab-rails` at `../robot_lab` and `../robot_lab-rails` — sibling checkouts in this same `robot_lab_project` workspace. If a robot_lab API doesn't behave as expected, the fix may belong in the sibling gem, not here. See `../CLAUDE.md` (one level up) for the multi-gem workspace map.

## Architecture: the pipeline state machine

The whole orchestration lives in two small services, deliberately kept separate from each other and from everything else:

- **`AgentRunner`** (`app/services/agent_runner.rb`) — the single entry point that starts an agent run. Guards "one running agent per task," stamps provider/model on the `Conversation` at creation time (never inferred later), increments `Task#workflow_run_count`, and enqueues `AgentRunJob`. Both the manual "Run" button (`AgentRunsController#create`) and the auto-chaining below call through this one path.
- **`AgentRunCompletionHandler`** (`app/services/agent_run_completion_handler.rb`) — runs after every `AgentRun` finishes and decides what (if anything) runs next. It reads only `Task` boolean flags (`planning_complete`, `workflow_complete`, `pr_agent_complete`, `blocked_reason`) that agents set via explicit tool calls — **never** parses agent prose/transcript to infer a verdict. Chains: planning stops (waits for human review) → implementation ↔ review alternate until review sets `workflow_complete` → PR agent runs once → done. Hits `Task::MAX_WORKFLOW_RUNS` (25) and it self-blocks with `blocked_reason: "max_iterations"`.

`AgentRunJob` runs one turn: builds a `RobotLab::Robot` scoped to `task.effective_cwd` (the worktree, or the project checkout if no worktree yet) with a tool set selected by `agent_type` (see `tools_for` in `app/jobs/agent_run_job.rb`), streams output into `TranscriptRecorder`, marks the run completed/failed, then schedules `AgentRunCompletionJob` after a 1-second settle delay to avoid a race with the just-written DB state.

Each agent type's system prompt lives in `app/prompts/{planning,implementation,review,pr}.md` (ERB + YAML front matter, rendered by `robot_lab`'s template system). **The prompts are the actual behavioral spec for each stage** — read them before changing an agent's tool set or the completion-handler's transition logic, since the two must stay in sync (e.g. only the review/pr/planning agents get `mark_*` completion tools; implementation never does — it just stops when done and review runs next automatically).

### Adding or changing pipeline behavior

- New agent stage: add a template in `app/prompts/`, a case branch in `AgentRunJob#tools_for`, and a transition in `AgentRunCompletionHandler`.
- Changing when the loop advances/stops: that's `AgentRunCompletionHandler` — it's intentionally the *only* place this logic lives.
- Changing what an agent can do: that's the tool list for its `agent_type` in `AgentRunJob#tools_for`, plus the corresponding tool class in `app/tools/`.

## Tools (`app/tools/`)

All agent-facing tools subclass `RobotLab::Tool` through one of two base classes:

- **`CodingTool`** (`cwd`-scoped: read/write/edit/glob/grep/bash) — `resolve_path` rejects any path that escapes `cwd`, so every filesystem tool call is confined to the task's worktree.
- **`TaskScopedTool`** (`task`-scoped, not `cwd`-scoped) — the task-doc read/write tools and the `mark_*` completion-signal tools (`TaskCompletionTool` subclasses). These flip `Task` boolean flags directly via ActiveRecord since this port runs in-process (unlike the original design's subprocess-CLI approach — see the comment in `task_completion_tool.rb`).

`BashTool` runs commands via `Open3.popen2e` with a process group and timeout (default 120s); it's the only tool that shells out arbitrarily. `WorktreeService` and `PrStatusService` also shell out but always via `Open3` with an argv array — never string interpolation into a shell — when adding new shell-invoking code, follow that pattern.

## The task doc

`TaskDocument` (`app/services/task_document.rb`) reads/writes a markdown scratchpad per task at `~/.robot_lab_experiment/projects/<project_id>/tasks/task-<task_id>.md` (root overridable via `ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT`). It deliberately lives **outside** the git worktree so it survives worktree teardown. It's the single shared state agents pass through the pipeline: the planning agent writes `## Original Request` / `## Overview` / `## Implementation Plan` / `## Testing Strategy` / `## To-Do List`; implementation checks off to-do items; review appends/replaces `## Review Findings`. The exact section structure in `app/prompts/planning.md` and `app/prompts/review.md` is a contract other prompts and the UI (`TasksController#show`) depend on — don't change the section names without updating both.

## Data model

`Project 1--* Task 1--* Conversation 1--1 AgentRun`, `Conversation 1--* Message`. A `Task` can have many `Conversation`s (one per `AgentRun`) but the UI/handler only ever care about the single currently-`running` one (`Task#running_agent_run`). `Message#msg_type` enumerates the full transcript vocabulary: `user`, `assistant`, `assistant_thinking`, `tool_use`, `tool_result`, `system`, `result` — `TranscriptRecorder` is the only writer, pairing each `tool_use` with the next `tool_result` (assumes sequential tool execution; see the caveat comment in that file if robot_lab ever turns on concurrent tool calls).

## Config

Default LLM provider/model live as constants in `AgentRunner` (`ollama` / local model), not in `config/robot_lab.yml` (that file doesn't exist here — robot_lab's config cascade falls through to gem defaults + `RubyLLM.configure` in `config/initializers/ruby_llm.rb`, which points at a local Ollama server). `config/initializers/orphan_agent_run_recovery.rb` sweeps any `AgentRun` still `running` to `failed` at boot, scoped only to `rails server`/`bin/jobs` processes (never console/runner/rake/tests) — a server restart mid-turn shouldn't leave a task stuck.

Background jobs run on Solid Queue (`bin/jobs`); no Redis/Sidekiq in this app.
