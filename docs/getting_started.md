# Getting Started

## Prerequisites

- Ruby (see `.ruby-version` in the repo for the exact version pinned)
- SQLite (bundled via the `sqlite3` gem — no separate server)
- Sibling checkouts of `robot_lab` and `robot_lab-rails` at `../robot_lab` and `../robot_lab-rails` relative to this repo (`Gemfile.local` points at them via `path:`) — this app is developed against the live gems in this workspace, not a released version
- **An LLM backend.** The app defaults every agent run to `openrouter` / `moonshotai/kimi-k2.7-code`, which needs `OPENROUTER_API_KEY` set. A local [Ollama](https://ollama.com) server is also pre-configured (`config/initializers/ruby_llm.rb` points at `http://localhost:11434/v1`) and can be used instead by passing an explicit `provider:`/`model:` — see [Configuration — LLM Provider](configuration.md#llm-provider) for how to actually do that, since neither the UI nor `AgentRunsController` currently expose a way to override the default per run.
- `gh` (GitHub CLI), authenticated, if you want PR creation, GitHub issue listing/filing (the `audit` stage), or accurate PR-status hints to actually work — these all shell out to `gh` and degrade to harmless placeholder text when it's absent or unauthenticated (see [Architecture — Best-Effort Services](architecture.md#best-effort-services-pr-status-github-issues)).

## Setup

```sh
bin/setup     # bundle install + db:prepare (idempotent — safe to re-run)
bin/dev        # Puma + the Tailwind watcher (Procfile.dev)
```

Visit the app (Puma's default port, typically `http://localhost:3000`).

## Creating a Project

A `Project` is just a pointer at a git repo already checked out on disk — the app never clones anything for you. From the Projects index, create one with:

- **Name** — a display label
- **Repo folder path** — an absolute path to an existing local git checkout (validated to actually contain a `.git` directory; the form rejects anything else)
- **Subproject path** *(optional)* — if the code you want the agents to work on lives in a subdirectory of that repo (a monorepo package), set this and every agent's working directory becomes `repo_folder_path/subproject_path` instead of the repo root (`Project#effective_cwd`)

The repo path can't be changed once the project has any tasks — `ProjectsController#update` silently drops that field from the update params in that case and flashes a warning instead of erroring, so existing tasks' worktrees (which are relative to the original path) never end up orphaned by an edit.

## Creating a Task and Running the Pipeline

From a Project's page, **New Task** takes a title and a free-form description (the description seeds the task doc's `## Original Request`; the title is used if the description is left blank). On create, the app:

1. Saves the `Task` row
2. Creates a dedicated `git worktree` for it (a sibling directory next to the repo, on its own branch — see [Architecture — Worktree Isolation](architecture.md#worktree-isolation-worktreeservice))
3. Seeds the task doc with the original request text

You'll land on the Task page, which shows the task doc (initially just your request) and a live transcript pane (empty until a run starts). The action buttons available reflect exactly what `Task#runnable_agent_types` currently allows — normally that's a single **Run planning** button to start:

| Button | What it does |
|---|---|
| **Run `<stage>`** | Starts the one next valid stage (`AgentRunner.start_agent_run`) — only ever shows the single stage that's actually next; see [Architecture — The State Machine](architecture.md#the-state-machine-agentrunner-agentruncompletionhandler) for exactly how that's decided |
| **Stop** | Cooperatively cancels the in-flight run (it stops between tool calls, not instantly) and pauses the pipeline so nothing auto-chains next |
| **Pause** | Lets the current run finish naturally, but stops it from auto-chaining into the next stage afterward |
| **Resume** | Clears a `blocked`/paused state so the pipeline can proceed again |
| **Abandon** | Cancels any in-flight run and permanently marks the task given up on |
| **Give the agents guidance** | Queues free-text guidance that gets prepended to the *next* run's kickoff message (and logged permanently into the task doc's `## Human Guidance` section) — to redirect a run already in progress, **Stop** it first, then send guidance |
| **Set status** dropdown | A manual override of the display-only `status` field — normally computed automatically (`Task#derived_status`); use this only when you need to force it (e.g. marking something done outside the normal pipeline) |

While a run is active, the status area shows a live spinner with an elapsed-time counter and message count, polled every 2 seconds from a small JSON heartbeat endpoint (`GET .../heartbeat`) — separate from the Turbo Streams transcript, which pushes new messages as they're written rather than being polled.

Planning stops itself after one run and waits here for you to read the plan (in the task doc) and click the next Run button yourself — every later transition (implementation ↔ review, then → PR) chains automatically without any button click, until the pipeline finishes, blocks, or hits its 25-run cap.

## Self-Auditing a Project

Every Project page also has a **Self-audit** action (`AuditTasksController#create`) — it creates a special `task_kind: "audit"` Task (titled `"Self-audit <timestamp>"`) whose only job is to investigate the codebase and file a GitHub issue for each concrete, verifiable problem it finds (capped at 10 issues per run — see [Tools Reference](tools_reference.md#creategithubissuetool)). An audit task runs its one `audit` stage and then stops permanently; it never enters the planning/implementation/review/PR pipeline.

## Development

```sh
bin/rails test                                        # full suite (Minitest, parallelized across CPUs)
bin/rails test test/models/task_test.rb                # single file
bin/rails test test/models/task_test.rb:23              # single test at a line
bin/rubocop                                             # lint (bin/rubocop -a to autocorrect)
bin/ci                                                  # setup, rubocop, bundler-audit, importmap audit, brakeman, tests, seed replant
```

`bin/ci` (via `config/ci.rb`) is the authoritative pre-push check — it's what would run in CI if hosted CI were enabled here (it isn't; see [Configuration — CI](configuration.md#ci)). Prefer it over piecing together individual commands before committing.

No RSpec — this app uses Minitest with fixtures (`test/fixtures/*.yml`), not factories.
