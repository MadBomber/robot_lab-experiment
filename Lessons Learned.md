# Lessons Learned

What `robot_lab-experiment` taught about putting Ruby LLM agents and their
streaming protocols inside a Rails + Hotwire application, grouped by layer.
Some lessons come from the claude_code bridge session (2026-11-21); others
were already built into the app's design (see `CLAUDE.md` and the code
comments for the reasons).

## Driving LLM agents from Rails

1. **Agents should report progress through tool calls, not prose.** The
   pipeline moves forward only when an agent calls something like
   `mark_planning_complete` or `mark_workflow_blocked`. Those calls set
   flags on the Task, and `AgentRunCompletionHandler` reads only the flags.
   It never tries to work out a verdict from what the model wrote. That is
   the main reason the loop works with very different models (Kimi on
   OpenRouter, a small LM Studio model, Claude Code).
2. **Keep the decision about what runs next in one place.** Starting runs
   (`AgentRunner`) and choosing the next stage (`AgentRunCompletionHandler`)
   are separate, small, and the only places that logic lives. When a stage
   gets stuck or loops, those are the only two files to read.
3. **"One running agent per task" has to be a database rule, not just a code
   check.** The code check is a fast shortcut, and the partial unique index
   is the real guarantee. Two clicks on Run, or a click racing an automatic
   chain, will get past an in-code check.
4. **Queue the job after the transaction commits.** Solid Queue keeps its
   jobs in a separate database, so a worker can pick up a job before the run
   row it needs exists. The extra one-second delay before
   `AgentRunCompletionJob` exists for the same reason.
5. **Clean up runs left behind by a crash.** A server restart mid-run used to
   leave a task "running" forever. The boot-time sweep marks those runs
   failed, and it runs only for the server and job processes, never in a
   console or during tests.
6. **Stop runaway agents with your own limits.** Models repeat themselves.
   `PlateauMonitor` catches the same call or result over and over within a
   run, `ProgressFingerprint` catches an implementation ↔ review cycle that
   makes no progress, and both send the task to a human instead of burning
   through 25 runs.

## Providers and the RubyLLM layer

7. **Not every provider supports tools.** Claude Code refuses RubyLLM tools,
   and robot_lab doesn't check for that, so every Claude Code run would have
   failed on its first turn. A provider that runs its own agent (a CLI like
   `claude -p`) needs a bridge, not a config change.
8. **MCP over stdio is a good bridge for an app with no login.** A server per
   run (`bin/task_mcp`) can only touch its one task and exits when the run
   ends. An HTTP endpoint inside Puma would have let any local process
   change any task's flags.
9. **Wrap existing tools; don't write them twice.** `McpToolAdapter` builds
   each MCP tool from the same tool object an lms or OpenRouter run uses,
   and `AgentToolset` is the single list of which stage gets which tools.
   With two lists, the two paths would drift apart.
10. **Isolate a spawned agent from the developer's own settings.** Without
    `--setting-sources project,local`, the Claude Code agent would load the
    developer's personal CLAUDE.md, including a rule against committing
    without being told, and the PR stage would refuse to commit. A CLI-based
    agent brings its owner's settings with it unless you stop it.
11. **Defaults built for remote APIs hurt local servers.** RubyLLM's retries
    turned a refused connection to a stopped LM Studio into about 8 seconds,
    every time the page rendered. The projects page took about 16 seconds
    to load. Quick checks against local servers need no retries and a short
    timeout (`Project.local_probe_config`). Real runs keep the normal
    settings.
12. **Ask local servers what models they have.** Local servers have no fixed
    model list, so the picker asks each one. Only chat models that can call
    tools are listed, because a model that can't call tools can't move the
    pipeline forward.

## Streaming and subprocesses

13. **Stopping a run means killing the whole process group.** An exception
    inside a `Popen3` block waits for the child to exit, so a "Stop" left
    `claude` running. The runner now kills the process group whenever the
    block exits early. The test for this checks timing, because a slow pass
    would have hidden the bug.
14. **Stdout belongs to the protocol.** A stdio MCP server breaks if anything
    else writes to stdout: Rails boot messages, gem warnings, a stray debug
    line. `bin/task_mcp` sends stdout to stderr while Rails boots, then
    hands it back to the MCP transport.
15. **The event stream is the only view into the agent.** With Claude Code,
    RubyLLM's tool callbacks never fire. The transcript, plateau detection
    and Stop all depend on the `on_event` hook reading Claude Code's
    stream-json, and an exception raised from that hook is what stops the
    run.
16. **Pair tool results by id, not by order.** The transcript recorder
    assumed each result belonged to the most recent call. Claude Code can
    make several calls before any results come back, so the recorder now
    matches each result to its call's `tool_use_id`.
17. **Only one process should write the transcript.** The MCP server
    deliberately records nothing. Message `seq` numbers are assigned in
    memory by the recorder, and a second writer would race it.

## Hotwire and the UI

18. **Broadcast from the place that records the data.** `TranscriptRecorder`
    both stores messages and appends them to the page. A partial that gets
    broadcast-replaced, like `task-toolbar`, has a fixed id and fixed inputs
    that you can't change without breaking the broadcast.
19. **Use native elements when you need to control many at once.**
    Collapsible transcript rows are plain `<details>` elements rather than a
    Poetry component, so one "Collapse tool calls" button can open or close
    all of them.
20. **Upgrading a front-end library can quietly change behavior.** Tailwind
    v4 changed button cursors from the hand to the arrow without any
    warning. The fix belonged in the app's own stylesheet, in the
    lowest-priority layer, not in the Poetry files that the next upgrade
    will overwrite.
21. **Know what your dev tools do without a terminal.** `bin/dev` shut
    itself down because the Tailwind watcher exits when it isn't attached to
    a terminal. Scripts and agents that launch the app have to start the web
    server and the job worker separately.

## Working process

22. **Prove a test can fail.** The process-kill test passed without the fix,
    only more slowly. Breaking the code on purpose to watch a test fail
    found that gap, and found the retry delay too.
23. **When a real test isn't possible, fake the outside tool, not your
    code.** With the Claude login expired, a fake `claude` script still ran
    the real job, the real `bin/task_mcp` and the real MCP traffic.
    Everything except the model was tested.
24. **Be careful with git operations around staged work.** Using `git stash`
    on one file to compare before and after quietly turned its staged
    changes into unstaged ones. `git stash --keep-index`, or a throwaway
    worktree, avoids it.

## Loose ends at the close of the experiment

- **claude_code 0.0.2 isn't published,** but the pushed `Gemfile.lock`
  depends on it, so installing the app's gems anywhere else fails until it
  is.
- **The Claude Code path hasn't run against a real model,** because the
  `claude` CLI login had expired.
