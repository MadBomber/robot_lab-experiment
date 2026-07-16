# robot_lab-experiment

An experiment, not a product. This app runs a four-stage AI coding pipeline
(planning → implementation → review → PR) against real git repositories,
using [`robot_lab`](../robot_lab) / [`robot_lab-rails`](../robot_lab-rails)
to drive LLM agents through the full loop with no human in it turn-to-turn.

It exists to explore what `robot_lab` itself is capable of -- an experimental
robot working on the robot_lab family of gems. **It is not meant for any
practical or production use.** Expect rough edges, dead ends, and pipeline
runs that go sideways; that's the point.

## Local LLMs only

This app is built around local models via [Ollama](https://ollama.com), not
hosted LLM APIs. `AgentRunner` defaults every agent run to the `ollama`
provider (see `app/services/agent_runner.rb`), and
`config/initializers/ruby_llm.rb` points RubyLLM at a local Ollama server:

```
http://localhost:11434/v1
```

Override the endpoint with `ROBOT_LAB_RUBY_LLM__OLLAMA_API_BASE` if Ollama
runs elsewhere. Have Ollama running with the target model pulled before
starting an agent run -- there's no fallback to a hosted provider.

## Getting started

```bash
bin/setup     # bundle install + db:prepare
bin/dev       # Puma + Tailwind watcher
```

Create a Project pointing at a local git repo, add a Task, and click Run to
kick off the pipeline. Each Task gets its own git worktree so runs never
touch your main checkout.

## Development

```bash
bin/rails test   # Minitest, parallelized
bin/rubocop       # lint
bin/ci            # full local CI: setup, rubocop, audits, brakeman, tests
```

## How it fits together

See [`CLAUDE.md`](CLAUDE.md) for the architecture: the `AgentRunner` /
`AgentRunCompletionHandler` state machine, the per-stage tool sets, and the
task-doc contract agents pass work through.
