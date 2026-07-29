# robot_lab-experiment

**An experiment, not a product.** A Rails 8.1 app that runs a four-stage AI coding pipeline — **planning → implementation → review → PR** — against real git repositories, driving `robot_lab`/`robot_lab-rails` LLM agents through the full loop with no human in it turn-to-turn. It exists to explore what `robot_lab` itself is capable of — an experimental robot working on the robot_lab family of gems. It is not meant for practical or production use; expect rough edges, dead ends, and pipeline runs that go sideways. That's the point.

```
Project  ──has many──▶  Task  ──has many──▶  Conversation  ──has one──▶  AgentRun
  (a git repo               (one pipeline        (one per                (one LLM turn)
   on disk)                  run, own worktree)    AgentRun)                   │
                                                                                ▼
                                                                     Message rows, ordered,
                                                                     broadcast live over
                                                                     Turbo Streams
```

A `Project` points at a git repo on disk. A `Task` under a project gets its own git worktree and runs through the pipeline one `AgentRun` at a time, with every LLM turn persisted as ordered `Message` rows and streamed live to the browser.

## Navigation

- [Getting Started](getting_started.md) — setup, prerequisites, creating a Project and Task, driving the pipeline from the UI
- [Architecture](architecture.md) — the pipeline state machine (`AgentRunner`/`AgentRunCompletionHandler`/`AgentRunJob`), the data model, the task-doc contract, plateau/progress detection
- [Tools Reference](tools_reference.md) — every agent-facing tool, the sandbox-level model, and which tools each pipeline stage gets
- [Configuration](configuration.md) — LLM provider setup, environment variables, MCP servers, background jobs, CI

## At a Glance

| | |
|---|---|
| **Framework** | Rails 8.1, Minitest (no RSpec), Solid Queue (no Redis/Sidekiq), SQLite |
| **Pipeline stages** | `planning` → `implementation` ↔ `review` (alternating) → `pr`; a fifth `audit` stage runs standalone |
| **Orchestration** | Two services: `AgentRunner` (starts a run) and `AgentRunCompletionHandler` (decides what runs next) — see [Architecture](architecture.md) |
| **Default LLM** | `openrouter` / `moonshotai/kimi-k2.7-code` (requires `OPENROUTER_API_KEY`) — a local Ollama server is also configured and usable by passing an explicit `provider:`/`model:` |
| **Isolation** | Each `Task` gets its own `git worktree`, sibling to the project checkout — concurrent tasks never collide |
| **Shared state across turns** | A markdown "task doc" per task, stored outside the worktree so it survives worktree teardown |
| **Sibling gem dependency** | `Gemfile.local` points `robot_lab`/`robot_lab-rails` at local sibling checkouts (`../robot_lab`, `../robot_lab-rails`) — this app tracks gem development live, not a released version |
| **GitHub Actions CI** | Intentionally disabled (`.github/workflows/ci.yml.disabled`) — the sibling-gem path dependency doesn't exist on a hosted runner. `bin/ci` is the real, local pre-push check |

## The Bottega Lineage

Comments throughout the codebase reference "Bottega" — the original design this app is a Ruby port of. Where you see a comment contrasting this port's behavior with "Bottega's TypeScript reference" or similar, that's intentional context about a deliberate implementation choice (e.g. this port runs tool calls in-process against ActiveRecord directly, where the original spawned a subprocess CLI per turn), not a stray TODO to resolve.

## Links

- [GitHub](https://github.com/MadBomber/robot_lab-experiment)
- Sibling gems in this workspace: [`robot_lab`](https://github.com/MadBomber/robot_lab), [`robot_lab-rails`](https://github.com/MadBomber/robot_lab-rails)
