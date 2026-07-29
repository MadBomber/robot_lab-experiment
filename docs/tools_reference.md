# Tools Reference

All agent-facing tools live in `app/tools/` and subclass `RobotLab::Tool` through one of two base classes, chosen by what the tool is scoped to.

## Base Classes

### `CodingTool` (`cwd`-scoped)

Base for every tool that reads or writes files: `ReadFileTool`, `WriteFileTool`, `EditFileTool`, `GlobTool`, `GrepTool`, `BashTool`, `CreateGithubIssueTool`, `ListGithubIssuesTool`. `cwd` is bound once at construction time (by whoever builds the `Robot` for a run — see `AgentRunJob#tools_for`), not read dynamically off the robot, since `RobotLab::Robot` has no built-in per-run context accessor for a tool to query.

#### The Sandbox Level Model

Every `CodingTool` has an effective **sandbox level** governing *read* access (write access is always `cwd`-confined regardless — see below). Precedence, highest to lowest:

1. An explicit `sandbox_level:` passed to the tool's constructor
2. A class-level override keyed by `agent_type` (`CodingTool.agent_type_override`)
3. The `AGENT_SANDBOX_LEVEL` environment variable (default `"tight"`)

| Level | Read scope | Used by (via the `agent_type` override) |
|---|---|---|
| `tight` | `cwd` only | `pr` (explicit override); the ENV default for anything unmapped |
| `loose` | `cwd` **+** every bundled gem's path (`Bundler.load.specs.map(&:full_gem_path)`, memoized) | `planning`, `implementation`, `audit` — lets them read into bundled dependency source when needed |
| `root` | `cwd` **+** bundled gem paths **+** `AGENT_READABLE_ROOT` (comma/newline-delimited extra directories, memoized) | `review` — the verification stage gets the widest read access, including any operator-configured extra roots |
| `none` | Unrestricted (`File.expand_path` with no confinement check at all) | Not currently reached by any of the five built-in agent types (all are explicitly mapped to one of the levels above) — only reachable via an explicit `sandbox_level: "none"` constructor arg, or by adding a new agent type without an override entry |

**Write access is always confined to `cwd`, at every sandbox level, with no exception.** `resolve_write_path` (used by `WriteFileTool`/`EditFileTool`) never consults `read_roots`/`readable_roots` — only `resolve_read_path` (used by `ReadFileTool`/`GlobTool`/`GrepTool`) does. This is why `AgentRunJob#tools_for` constructs `WriteFileTool`/`EditFileTool` with an explicit `sandbox_level: "tight"` even for stages whose *read* level is `"loose"` — that argument is documentation of intent, not a functional requirement, since writes ignore it either way and are always `cwd`-only.

Path confinement itself walks up from the target path to the deepest existing ancestor, resolves *that* via `File.realpath` (so symlinks can't be used to point outside the sandbox), and checks the result is the confinement root or a real subdirectory of it — not merely a string prefix match, which a crafted path could otherwise defeat.

### `TaskScopedTool` (`Task`-scoped, not `cwd`-scoped)

Base for tools bound to a `Task` rather than a directory: the task-doc read/write tools, and every completion-signal tool (via the further subclass `TaskCompletionTool`). These flip `Task` boolean flags directly via ActiveRecord, since this port runs entirely in-process — unlike the original Bottega design's subprocess-CLI approach for the same signal, this Rails port just updates the row directly from inside the tool call.

## File & Search Tools

### `ReadFileTool`

Reads one file's full contents. Raises if the resolved path isn't a real file.

### `WriteFileTool`

Writes (creating parent directories as needed) — full overwrite, no diffing. Returns a byte-count confirmation string.

### `EditFileTool`

Exact-string find/replace. `old_string` must occur exactly once unless `replace_all: true` is passed, and the tool raises with the match count if it's ambiguous rather than guessing which occurrence was meant. Replacement uses the block form of `sub`/`gsub` so a `new_string` containing `\0`, `\1`, etc. is treated as literal text, not a regexp backreference.

### `GlobTool`

`Dir.glob` scoped to (and filtered by) the current sandbox level's read scope. Returns matching paths relative to `cwd`, one per line.

### `GrepTool`

Ruby-regexp content search across files matching an optional glob, also filtered by the read sandbox. Caps output at `GrepTool::MAX_MATCHES` (200) total, across all files — a backstop against flooding the transcript with matches from a bad pattern. Skips (rather than errors on) files that raise `ArgumentError` while being read line-by-line — the tool's way of quietly skipping binary files.

### `BashTool`

Runs an arbitrary shell command via `Open3.popen2e` (combined stdout+stderr) in a dedicated process group, with a timeout (`BashTool::DEFAULT_TIMEOUT` = 120s, overridable per call) enforced by killing the whole process group (`Process.kill("-TERM", ...)`) on expiry. Explicitly documented as **outside** the Ruby-level read sandbox: a shell command is confined by `chdir` to the working directory, but can otherwise reach the host filesystem, network, and secrets through the OS the same way any shell command can — meaning the `"none"` read level doesn't materially expand what a determined caller could already do via `BashTool` alone. This is a different thing from `RobotLab::ScriptTool` (core gem) — that's a factory for wrapping pre-existing executable script *files* (the AgentSkills pattern), not a general command runner.

## Task Doc Tools

### `ReadTaskDocTool`

Returns `TaskDocument.read(task)` verbatim — the current markdown scratchpad content.

### `WriteTaskDocTool`

Overwrites the task doc — a full replace, same "read it first" caveat as `WriteFileTool`. Returns a byte-count confirmation.

## Completion Tools (`TaskCompletionTool` subclasses)

Each of these flips exactly one `Task` flag and is the *only* way the pipeline advances or stops on an agent's say-so — `AgentRunCompletionHandler` reads these flags and never the agent's transcript prose.

### `MarkPlanningCompleteTool`

Sets `planning_complete: true`. Called by the `planning` stage once the plan doc is fully written and verified by reading it back.

### `MarkWorkflowCompleteTool`

Sets `workflow_complete: true` (the review stage's READY verdict) — triggers the `pr` stage to start next.

### `MarkWorkflowBlockedTool`

Sets `blocked_reason: "human_requested"` — the review stage's BLOCKED verdict, for work that genuinely needs a human decision, credential, or external action no agent can perform.

### `MarkPrCompleteTool`

The one completion tool that **doesn't blindly trust the agent's word.** Before flipping `pr_agent_complete: true`, it independently verifies (via `git`/`gh`, all through `Open3` with an argv array) that the claimed work actually exists:

1. **Dirty worktree?** → refuses, telling the agent to commit and push first
2. **Nothing committed ahead of the base branch, and nothing uncommitted?** → genuinely nothing to submit; completes immediately (no PR needed)
3. **No GitHub remote configured?** → a committed branch is the deliverable on a remote-less checkout; completes without requiring a PR
4. **Remote exists but no open PR for this branch?** → refuses, telling the agent to push and open one

This exists because a small local model could otherwise call `mark_pr_complete` while work sits uncommitted and no PR exists at all — and since the orchestrator by design never parses prose to catch that, the tool itself has to be the one that refuses to lie. Each check (`dirty_worktree?`, `commits_ahead?`, `remote_configured?`, `open_pr?`) is independently public and testable.

## GitHub Issue Tools (audit stage)

### `ListGithubIssuesTool`

Lists open issues (`gh issue list`) so the audit agent can check what's already filed before investigating — avoiding duplicate issues.

### `CreateGithubIssueTool`

Files one issue via `gh issue create`. Caps itself at `MAX_ISSUES_PER_RUN` (10) — a hard backstop against a runaway local model filing dozens of issues, independent of (and in addition to) the audit prompt's own "file at most 10" instruction. The counter is instance-scoped and a fresh tool instance is built per `AgentRunJob#perform`, so this caps issues **per audit run**, not for the repository's entire lifetime.

## Which Stage Gets Which Tools

From `AgentRunJob#tools_for` — every stage also gets `ReadTaskDocTool`/`WriteTaskDocTool` in addition to what's listed:

| Stage | Tools (beyond the task-doc pair) |
|---|---|
| `planning` | `ReadFileTool`, `GlobTool`, `GrepTool`, `MarkPlanningCompleteTool` — **no** `BashTool` and **no** write tools; planning is read-only exploration plus writing the plan into the task doc |
| `implementation` | `ReadFileTool`, `WriteFileTool`, `EditFileTool`, `GlobTool`, `GrepTool`, `BashTool` — **no** completion tool; it just stops when its to-do items are checked off |
| `review` | `ReadFileTool`, `GlobTool`, `GrepTool`, `BashTool`, `MarkWorkflowCompleteTool`, `MarkWorkflowBlockedTool` — **no** write tools; review verifies and runs tests, it never edits code itself |
| `pr` | `BashTool`, `MarkPrCompleteTool` — no file tools at all; everything happens through git/gh commands |
| `audit` | `ReadFileTool`, `GlobTool`, `GrepTool`, `ListGithubIssuesTool`, `CreateGithubIssueTool` — read-only against the repo, write-only against GitHub issues |

Only the `review` stage is given MCP server tools (see [Configuration — MCP Servers](configuration.md#mcp-servers)) — it's the verification stage, so it's the one stage that gets browser/external-tool access; every other stage gets none.

Note the deliberate absence of `RobotLab::AskUser` anywhere in this list: it reads from `$stdin`/`$stdout`, which has no meaningful source inside a background job — using it would simply hang the run. Where an agent (planning, in practice) hits a genuine ambiguity, the prompt instructs it to make a reasonable assumption and document it, rather than ask.
