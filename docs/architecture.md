# Architecture

## Data Model

```
Project 1──* Task 1──* Conversation 1──1 AgentRun
                          │
                          └──* Message
```

| Model | Key fields | Notes |
|---|---|---|
| `Project` | `name`, `repo_folder_path`, `subproject_path` | `repo_folder_path` must be a real git checkout (validated); `effective_cwd` joins in `subproject_path` when set |
| `Task` | `title`, `status`, `task_kind` (`fix`/`audit`), `worktree_path`, `branch_name`, `planning_complete`, `workflow_complete`, `pr_agent_complete`, `blocked_reason`/`blocked_detail`/`blocked_run_id`, `workflow_run_count`, `no_progress_streak`, `progress_fingerprint`, `pending_guidance` | The pipeline's entire state lives in these boolean/string flags — see [The State Machine](#the-state-machine-agentrunner-agentruncompletionhandler) |
| `Conversation` | `provider`, `model`, `started_at` | One per `AgentRun`; provider/model are stamped here at creation and never re-inferred later |
| `AgentRun` | `agent_type` (`planning`/`implementation`/`review`/`pr`/`audit`), `status` (`pending`/`running`/`completed`/`failed`/`blocked`/`cancelled`), `cancel_requested` | One LLM turn |
| `Message` | `msg_type` (`user`/`assistant`/`assistant_thinking`/`tool_use`/`tool_result`/`system`/`result`), `seq`, `uuid`, `payload` (JSON) | The full transcript vocabulary; `TranscriptRecorder` is the only writer — see [below](#the-message-transcript-transcriptrecorder) |

A `Task` can have many `Conversation`s (one per `AgentRun` it has ever started) but the UI and the completion handler only ever care about the single currently-`running` one — `Task#running_agent_run`.

`Task#status` (`pending`/`in_progress`/`in_review`/`completed`) is **display-only**, derived by `Task#derived_status` from the same boolean flags `runnable_agent_types` uses. It never drives branching logic itself — `recompute_status!` is called defensively after state changes, but the real state machine lives entirely in the flags below, not in this enum. It's safe to recompute freely at any time without touching real pipeline logic.

## The State Machine: `AgentRunner` / `AgentRunCompletionHandler`

The whole orchestration lives in two small services, deliberately kept separate from each other and from everything else in the app.

### `AgentRunner` — starting a run

The single entry point for starting *any* agent run — both the manual "Run" button (`AgentRunsController#create`) and `AgentRunCompletionHandler`'s auto-chaining call through this one path; there is no separate code path for the two.

```ruby
AgentRunner.start_agent_run(task, "implementation")  # provider/model default from AgentRunner constants
```

It:

1. Raises `AgentRunner::AlreadyRunningError` if the task already has a `running` `AgentRun` (the one-running-agent-per-task rule)
2. Increments `Task#workflow_run_count`
3. Creates the `Conversation`, stamping `provider`/`model` **explicitly at creation time** — never inferred later from context
4. Creates the `AgentRun` (`status: "running"`)
5. Enqueues `AgentRunJob.perform_later`

`DEFAULT_PROVIDER`/`DEFAULT_MODEL` are constants on `AgentRunner` itself (`"openrouter"` / `"moonshotai/kimi-k2.7-code"` as of this writing — see [Configuration](configuration.md#llm-provider) for how to actually override them, since neither the controller nor the UI currently pass a different `provider:`/`model:` through).

### `AgentRunJob` — running one turn

Builds a `RobotLab::Robot` scoped to `task.effective_cwd` (the worktree, or the project checkout if no worktree exists yet), with a tool set selected by `agent_type` (see [Tools Reference](tools_reference.md)), runs one turn, and always — success, failure, or cancellation — schedules `AgentRunCompletionJob` after a 1-second settle delay (`AgentRunJob::SETTLE_DELAY`), to avoid a race between the just-written `AgentRun`/`Task` state and the completion handler reading it.

```ruby
robot.run(kickoff_message(task), tools: :inherit)
```

The explicit `tools: :inherit` matters: `RobotLab::Robot#run` has its own `tools: :none` default independent of the `local_tools:` passed to `RobotLab.build` — omitting it here would silently wipe the tool list to empty on every single turn, and the LLM would never see any of the tools built for it.

The kickoff message is `"Begin."` normally, or — when `Task#pending_guidance` is present — that guidance prepended and consumed (cleared) for exactly this one run:

```
A human overseeing this task has provided the following guidance. Follow it,
adjusting your plan as needed:

<guidance text>

Begin.
```

Three outcomes, each handled distinctly:

| Outcome | Trigger | Result |
|---|---|---|
| Normal completion | the robot's turn finishes | `AgentRun#status = "completed"` |
| **Cancelled** | a human clicked Stop/Abandon; the `on_tool_call` callback re-checks `agent_run.reload.cancel_requested?` before every tool call and raises `AgentRunJob::Cancelled` | `AgentRun#status = "cancelled"` — not treated as a failure |
| **Plateaued** | `PlateauMonitor::Plateaued` or `RobotLab::ToolLoopError` raised mid-run | `AgentRun#status = "blocked"`, and the whole `Task` is blocked (`blocked_reason: "no_progress"`) so a human can inspect and unblock rather than burning more runs |
| Any other error | any other `StandardError` | `AgentRun#status = "failed"` (logged; not automatically retried) |

Regardless of outcome, the `ensure` block disconnects the robot's MCP clients (tearing down their stdio subprocesses) and finishes the transcript recorder.

### `AgentRunCompletionHandler` — deciding what runs next

The **entire** state machine lives in this one class — intentionally the only place this branching logic exists. It reads only `Task` boolean flags that agents set via explicit tool calls; it **never** parses agent prose or transcript to infer a verdict. Runs (via `AgentRunCompletionJob`, after the settle delay) once every `AgentRun` finishes, regardless of how it finished.

Decision order, each returning a `Result = Data.define(:action, :next_agent_run)`:

1. **The run failed** → stop; no chain (`:failed_no_chain`)
2. **The run was `planning`** → stop; wait for a human to review the plan (`:stopped_after_planning`) — planning never auto-chains into implementation
3. **The run was `audit`** → stop; audit tasks are one-shot (`:stopped_after_audit`)
4. **`Task#workflow_complete?`** (review said READY) → start the `pr` stage if not already `pr_agent_complete?`, else stop (`:already_complete`)
5. **`Task#blocked?`** → stop (`:stopped_blocked`)
6. **`Task#iteration_cap_reached?`** (`workflow_run_count >= 25`) → block the task (`blocked_reason: "max_iterations"`) and stop
7. **Plateau check** (see [below](#cross-run-plateau-detection-progressfingerprint)) → if the task hasn't moved in several impl↔review cycles, block it (`blocked_reason: "no_progress"`) and stop, rather than grinding to the iteration cap
8. Otherwise: **alternate** — an `implementation` run chains to `review`; anything else (i.e. a `review` run that didn't set `workflow_complete`) chains back to `implementation`

Every branch also broadcasts an updated task header over Turbo Streams (`broadcast_task_header`), so the UI's Run/Stop/Pause buttons and status line update live without a page refresh, regardless of which service (this handler, a controller action) triggered the change.

### Why Two Services, Not One

`AgentRunner` only knows how to *start* a run; it has no opinion about what comes next. `AgentRunCompletionHandler` only knows how to *decide what's next*; it delegates the actual starting back to `AgentRunner`. This separation is why the manual "Run" button and the automatic chaining share one code path exactly — a controller action calling `AgentRunner` directly is indistinguishable, from `AgentRunner`'s point of view, from the completion handler calling it after a prior run finished.

## Pipeline Stages and Prompts

Each agent type's system prompt lives in `app/prompts/{planning,implementation,review,pr,audit}.md` — ERB templates with YAML front matter, rendered through `robot_lab`'s own template system. **These prompts are the actual behavioral specification for each stage** — the completion handler's transition logic and each prompt's instructions must stay in sync (for example: only the `review`/`pr`/`planning` agents are given `mark_*` completion tools; `implementation` is never given one — it just stops when its to-do items are checked off, and `review` runs next automatically per the handler above).

| Stage | Job | Terminal signal |
|---|---|---|
| `planning` | Turn the task doc's original request into a full plan (`## Overview`, `## Implementation Plan`, `## Testing Strategy`, `## To-Do List`) | `mark_planning_complete` |
| `implementation` | Check off unchecked to-do items, address any `## Review Findings` from a prior pass first | *(none — just stops; review runs next automatically)* |
| `review` | Independently, skeptically verify every checked item against the plan, then run tests | `mark_workflow_complete` (READY), `mark_workflow_blocked` (BLOCKED), or neither (NEEDS_WORK — replaces `## Review Findings` and stops, implementation runs next) |
| `pr` | Commit, push, open (or verify) the PR | `mark_pr_complete` — but only after independently verifying the artifacts actually exist; see [Tools Reference](tools_reference.md#markprcompletetool) |
| `audit` | Read-only: investigate the repo, file a GitHub issue per concrete problem found | *(none — always a single, terminal run)* |

## The Task Doc

`TaskDocument` (`app/services/task_document.rb`) is the single piece of shared state that survives across every turn of the pipeline — a markdown scratchpad per task at:

```
~/.robot_lab_experiment/projects/<project_id>/tasks/task-<task_id>.md
```

(root overridable via `ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT`). It deliberately lives **outside** the git worktree, so it survives worktree teardown (task deletion, PR merge) — a plain file, not a database row, not committed to the repo the agents are working on.

The section structure is a **contract**, not a convention — `app/prompts/planning.md`/`review.md` write these exact `## `-level headings, `ProgressFingerprint` (below) parses `## Review Findings` and counts `- [x]` checkboxes by regex, and `TasksController#show` renders the whole doc as plain preformatted text. Changing a section name requires updating the prompts, `ProgressFingerprint`, and the view together:

```
## Original Request       (planning quotes the task's original text verbatim — never paraphrased)
## Overview
## Implementation Plan
## Testing Strategy
## To-Do List
### Implementation
### Testing
## Review Findings        (written/replaced by the review stage; not present until the first review pass)
## Human Guidance          (appended by TasksController#guide; persists across every future re-read)
```

`TaskDocument.seed` writes the initial request at task-creation time; `append_guidance` is additive (keeps every past guidance entry); everything else is a full overwrite (`WriteTaskDocTool`/`WriteFileTool` doesn't diff — the writer is expected to have read the doc first).

## Worktree Isolation (`WorktreeService`)

Every `Task` gets its own `git worktree` — a sibling directory next to the project's checkout, never inside it, on a dedicated branch (`task/<id>-<sanitized-title>`):

```
/path/to/repo                    # the Project's checkout — never touched
/path/to/repo-worktrees/task-42  # this Task's isolated worktree
```

Created at `TasksController#create` time (transactionally with the `Task` row — a `WorktreeService::Error` rolls the whole creation back), and removed at task deletion. `WorktreeService#remove` treats "already gone" as benign (git itself errors on removing a non-existent worktree, which this service swallows as a no-op success) but surfaces a real failure — permissions, locked files, corrupt state — that would otherwise leave a directory behind silently. Branch deletion afterward is best-effort: a missing branch is a normal, benign state that must never block teardown.

All git invocations go through `Open3.capture3` with an argv array — never string interpolation into a shell — matching the same convention `PrStatusService`, `GithubIssueService`, and (in the sibling `robot_lab-to` gem) `CommitManager` all follow.

## The Message Transcript (`TranscriptRecorder`)

One instance per `AgentRunJob#perform` call (not safe to share across runs). Persists a conversation's streaming LLM output as ordered `Message` rows and broadcasts a live transcript view over Turbo Streams as it goes.

Streaming chunks carry **deltas**, not a running total, so `TranscriptRecorder` buffers `content`/`thinking` text and flushes one `Message` row per contiguous run of the same kind — not one row per token. Thinking text is flushed into the persisted transcript for later review but is **never broadcast live**; only a spinner (`Cyborg`-style status, not literal thinking text) indicates the agent is working while it thinks or acts.

Tool call/result pairing assumes **sequential** tool execution — the recorder naively pairs "the last `tool_use`" with the next `tool_result` it sees. If `robot_lab` ever enables concurrent tool execution, this pairing would need to become a proper id-keyed queue instead of "last call wins" — noted directly in the source as a real caveat, not a hypothetical.

## Cross-Run Plateau Detection (`ProgressFingerprint`)

A stable SHA-256 hash of everything that *should* change when a task genuinely moves forward one `implementation` ↔ `review` cycle:

- how many `- [x]` to-do items are checked in the task doc
- the content of the `## Review Findings` section
- the worktree's uncommitted diff plus its current `HEAD` commit (did implementation actually change code?)

`Task#record_progress!` compares this fingerprint cycle-over-cycle: unchanged → increment `no_progress_streak`; changed → reset it to 0 and store the new fingerprint. `Task#plateaued?` is true once that streak reaches `Task::NO_PROGRESS_LIMIT` (3 — roughly two full impl↔review cycles of zero movement). `AgentRunCompletionHandler` checks this on every completion and blocks the task (`blocked_reason: "no_progress"`) rather than letting it grind on to the 25-run iteration cap while accomplishing nothing.

This is a **cross-run** detector — it looks at whether the *task* moved between completed runs. `PlateauMonitor` (below) is a separate, **within-run** detector watching a single run's own tool-call behavior.

## Within-Run Plateau Detection (`PlateauMonitor`)

A per-run monitor (constructed fresh per `AgentRunJob#perform`, fed from the `Robot`'s `on_tool_call`/`on_tool_result` callbacks) that raises `PlateauMonitor::Plateaued` the moment a *single run* stops making forward progress — killing a stuck run after a handful of wasted calls instead of hundreds.

This exists because `robot_lab`'s own `DoomLoopDetector` only tracks tool *names* and injects a soft warning the LLM can (and, in practice, did — for 172 calls in one observed run) simply ignore. `PlateauMonitor` instead keys on the tool call's *arguments* and its *result*:

| Signal | Limit | Distinguishes |
|---|---|---|
| Identical `(tool, arguments)` call, consecutively | `IDENTICAL_CALL_LIMIT` = 4 | "run the tests 3 times" (legitimate) from "poll the same failing command forever" (stuck) |
| Identical result payload, consecutively | `IDENTICAL_RESULT_LIMIT` = 6 | a normal edit→test→edit debug loop (results differ between repeats) from a genuine "nothing is changing" loop — counted *consecutively*, so one differing result in between resets the streak |
| Total tool calls in the run | `MAX_TOOL_CALLS` = 200 | a coarse backstop for a run that never repeats but also never stops; kept generous so a legitimately busy implementation run (many varied reads/edits/test runs) isn't guillotined — the two finer detectors above trip on a real loop long before this ceiling matters |

`robot_lab`'s own `max_tool_rounds` circuit breaker (set to `PlateauMonitor::MAX_TOOL_CALLS` when building the robot) is the coarser backstop underneath this one.

## Best-Effort Services: PR Status, GitHub Issues

`PrStatusService` and `GithubIssueService` both shell out to `gh` and are explicitly **never load-bearing** — a missing or unauthenticated `gh` CLI degrades to a harmless placeholder ("No pull request open yet...", an empty issue list) rather than raising and breaking a page load. `PrStatusService`'s output only ever feeds the `pr` stage's prompt as a hint (the PR agent verifies the real state itself via the shell); `GithubIssueService` backs the New Task "prefill from issue" flow and the Project page's open-issues list.

## Cancellation

Stop/Abandon (`TasksController#stop`/`#abandon`) don't kill anything synchronously — they set `AgentRun#cancel_requested = true` and mark the `Task` blocked immediately. The actual in-flight `AgentRunJob` notices cooperatively: its `on_tool_call` callback reloads the `AgentRun` and raises `AgentRunJob::Cancelled` before the *next* tool call executes, so cancellation takes effect between tool calls, not instantly mid-call.

## Orphan Recovery

A background job executing a streaming `Robot` turn is in-memory work — a server or worker restart mid-turn would otherwise leave its `AgentRun` stuck at `status: "running"` forever. `config/initializers/orphan_agent_run_recovery.rb` sweeps every `running` `AgentRun` to `failed` at boot, but only in an actual server/worker process (`Rails::Server` or `bin/jobs`) — never console, runner, rake, or the test suite — so a task left stuck by a crash is simply re-triggerable rather than silently blocked forever.
