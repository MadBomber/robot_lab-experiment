# Changelog

All notable changes to this project are documented here.

## 2026-08-28

### Added

- Redesigned the task show page as a "pipeline console": a stepper for the
  planning/implementation/review/pr stages, a color-coded and collapsible
  transcript (per `msg_type`, with tool calls/results and thinking blocks
  collapsible individually or all at once), and a sidebar with task status,
  actions, guidance, the task doc, and a legend.
- `Task#current_pipeline_stage` and `Task#pipeline_stage_status` to drive the
  stepper from the same completion flags `runnable_agent_types` already reads.
- `MessagesHelper` for per-message-type icons and collapsed-entry summary
  lines in the transcript.
- Presence/inclusion validators on `Task`, `AgentRun`, and `Message` for every
  NOT NULL column that lacked one (`active_record_doctor`). Booleans use
  `inclusion: { in: [true, false] }` rather than `presence: true`, which would
  incorrectly reject `false`; `Message#payload` uses `exclusion: { in: [nil] }`
  so an empty Hash stays valid while `nil` doesn't.

### Changed

- Dropped two redundant single-column indexes (`messages.conversation_id`,
  `agent_runs.task_id`), each already covered by a composite index, and
  replaced `agent_runs.conversation_id`'s index with a unique one to match its
  `has_one` usage on `Conversation`.
- `.rubocop.yml` excludes `Archspec.rb` from `Naming/FileName` -- its required
  capitalized filename is a tool convention (like `Gemfile`/`Rakefile`), not
  something to rename.

### Fixed

- `_task_controls` used `task.pending_guidance.present?` instead of the
  `pending_guidance?` query attribute (`rails_best_practices`).
