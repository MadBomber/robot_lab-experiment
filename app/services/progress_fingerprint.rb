require "digest"
require "open3"

# Cross-run plateau detection: a stable hash of everything that should change
# when a task actually moves forward one impl<->review cycle. If it's identical
# across consecutive completion cycles, the pipeline is oscillating without
# progress (the Task 15 / Task 21 failure), and AgentRunCompletionHandler blocks
# the task instead of looping to the 25-run cap.
#
# Signals (any real progress moves at least one of them):
#   - how many to-do items are checked off in the task doc,
#   - the worktree's uncommitted diff + HEAD (did implementation change code?),
#   - the "## Review Findings" section (did review say something new?).
module ProgressFingerprint
  module_function

  def for(task)
    Digest::SHA256.hexdigest(signals(task).join("\x1e"))
  end

  def signals(task)
    doc = TaskDocument.read(task)
    [
      checked_todo_count(doc).to_s,
      section(doc, "Review Findings"),
      worktree_state(task)
    ]
  end

  def checked_todo_count(doc)
    doc.scan(/^\s*-\s*\[x\]/i).size
  end

  # The named "## Section" body, up to the next "## " heading (or end of doc).
  def section(doc, heading)
    match = doc.match(/^##\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^##\s|\z)/mi)
    match ? match[1].strip : ""
  end

  # Uncommitted changes + current HEAD in the task's worktree. Returns "" when
  # there's no worktree yet (planning stage) so the signal is simply neutral.
  def worktree_state(task)
    cwd = task.worktree_path
    return "" if cwd.blank? || !Dir.exist?(cwd)

    diff, _s = Open3.capture2("git", "status", "--porcelain", chdir: cwd)
    head, _s = Open3.capture2("git", "rev-parse", "HEAD", chdir: cwd)
    "#{head.strip}\n#{diff}"
  rescue StandardError
    ""
  end
end
