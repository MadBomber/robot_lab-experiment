# Configuration

## LLM Provider

Default provider/model live as **constants on `AgentRunner`** (`app/services/agent_runner.rb`), not in `config/robot_lab.yml` (that file doesn't exist in this app — `robot_lab`'s own config cascade falls through to gem defaults, layered with `RubyLLM.configure` below):

```ruby
DEFAULT_PROVIDER = "openrouter".freeze
DEFAULT_MODEL = "moonshotai/kimi-k2.7-code".freeze
```

Using the default requires `OPENROUTER_API_KEY` to be set — `RubyLLM` does not auto-populate this from the environment the way it does for some other providers, so every OpenRouter request fails auth without it.

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.ollama_api_base = ENV.fetch("ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE", "http://localhost:11434/v1")
  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
end
```

A local Ollama server is configured here too (`/v1` is required — Ollama's OpenAI-compatible server only listens on `/v1/chat/completions`, not bare `/chat/completions`, and RubyLLM's Ollama provider has no built-in fallback the way its OpenAI provider does). Override the endpoint with `ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE` if Ollama runs elsewhere.

**To actually use Ollama instead of the OpenRouter default**, since neither the UI nor `AgentRunsController` currently expose a provider/model override, call `AgentRunner.start_agent_run` directly with explicit keywords (from a console, a rake task, or a code change to the controller):

```ruby
AgentRunner.start_agent_run(task, "planning", provider: "ollama", model: "qwen3.6")
```

Have Ollama running with the target model already pulled first — there's no fallback to a hosted provider if it isn't reachable.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `OPENROUTER_API_KEY` | *(none)* | Required for the default `openrouter` provider to authenticate at all |
| `ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE` | `http://localhost:11434/v1` | Where to reach an Ollama server, if used |
| `ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT` | `~/.robot_lab_experiment` | Root directory for task docs (`TaskDocument`) |
| `AGENT_SANDBOX_LEVEL` | `tight` | Fallback read-sandbox level for any `CodingTool` whose `agent_type` isn't explicitly overridden (all five built-in stages currently are — see [Tools Reference](tools_reference.md#the-sandbox-level-model)) |
| `AGENT_READABLE_ROOT` | *(empty)* | Comma- or newline-delimited extra directories readable at the `"root"` sandbox level (currently only the `review` stage) |
| `MCP_CONFIG_PATH` | `config/mcp_servers.json` | Path to the MCP server config file (see below); tilde-expanded, so e.g. `~/.mcp.json` works |

## MCP Servers

`McpConfigNormalizer` reads a Claude-Desktop/Cursor/`~/.mcp.json`-style config file (JSON or YAML, with ERB interpolation available for secrets) and normalizes it into the array of server specs `RobotLab.build(mcp_servers:)` expects:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

normalizes to:

```ruby
[{ name: "playwright", transport: { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }]
```

Transport type is taken from an explicit `"type"` key when present (`stdio`/`sse`/`http`/`streamable-http`/`ws`, with a few synonym spellings normalized), or inferred otherwise: a `command` implies `stdio`, a bare `url` implies `streamable-http`. `RobotLab` itself owns the actual MCP client lifecycle (connect, tool injection, disconnect via `Robot::MCPManagement`) — this class only translates the portable config file format into the spec array `RobotLab.build` consumes.

No `config/mcp_servers.json` ships in this repo by default — `McpConfigNormalizer.call` returns `[]` when the file is absent, and `AgentRunJob#mcp_servers_for` catches `McpConfigNormalizer::Error` on a malformed file, logging a warning and falling back to `[]` (an MCP config mistake degrades the review stage to no MCP tools, rather than crashing the run). Only the `review` stage is ever given MCP servers at all — see [Tools Reference](tools_reference.md#which-stage-gets-which-tools).

## Background Jobs

Solid Queue (`bin/jobs` runs the worker process) — no Redis, no Sidekiq. `AgentRunJob` and `AgentRunCompletionJob` both `queue_as :default`.

## Orphan Run Recovery

See [Architecture — Orphan Recovery](architecture.md#orphan-recovery) for the mechanism; the short version is that any `AgentRun` still `status: "running"` at boot in an actual server/worker process gets swept to `"failed"`, so a crash never leaves a task permanently stuck.

## CI

`bin/ci` (backed by `config/ci.rb`, `ActiveSupport::ContinuousIntegration`) runs: setup, RuboCop, `bundler-audit`, an importmap audit, Brakeman, the full test suite, and a seed replant. This is the authoritative pre-push check for this repo.

**GitHub Actions CI is intentionally disabled** — the workflow file is committed as `.github/workflows/ci.yml.disabled` (the `.disabled` suffix keeps GitHub Actions from picking it up at all; do not rename it to `ci.yml`). The reason: hosted CI runs against the plain `Gemfile`, which does **not** include `robot_lab`/`robot_lab-rails` — those are declared only in `Gemfile.local` as local `path:` gems pointing at sibling checkouts that simply don't exist on a hosted runner. With them absent, `RobotLab` is an undefined constant and every tool test errors out immediately. This can only be fixed once `robot_lab`/`robot_lab-rails` are published as released gems this app can depend on normally; until then, `bin/ci` locally (which uses `Gemfile.local`) is the real check.

A separate, still-active workflow (`.github/workflows/deploy-github-pages.yml`) builds and publishes this `docs/` directory via MkDocs to GitHub Pages on every push to `main`/`develop` that touches `docs/**` or `mkdocs.yml` — unrelated to, and unaffected by, the disabled application CI workflow above.

## Gemfile.local — the Sibling-Gem Dependency

`Gemfile.local` (loaded via `eval_gemfile "Gemfile"`, and what `bundle install`/every `bin/*` script actually uses) points `robot_lab` and `robot_lab-rails` at `../robot_lab` and `../robot_lab-rails` — sibling checkouts in this same `robot_lab_project` workspace, not released gem versions. If a `robot_lab` API doesn't behave as documented or expected while working in this app, the fix likely belongs in the sibling gem, not here — see the workspace-level `CLAUDE.md` one level up for the full multi-gem map.
