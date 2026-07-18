# Reads and writes the markdown doc that is a Task's shared scratchpad across
# agent turns. Lives outside any git worktree so it survives worktree teardown
# (worktree removal happens at task delete / PR merge; the doc must outlive both).
module TaskDocument
  module_function

  def archive_root
    File.expand_path(ENV.fetch("ROBOT_LAB_EXPERIMENT_ARCHIVE_ROOT", "~/.robot_lab_experiment"))
  end

  def doc_path(task)
    File.join(archive_root, "projects", task.project_id.to_s, "tasks", "task-#{task.id}.md")
  end

  def read(task)
    path = doc_path(task)
    File.exist?(path) ? File.read(path) : ""
  end

  def write(task, content)
    path = doc_path(task)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def seed(task, original_request)
    write(task, original_request.to_s)
  end

  # Append a human redirect (#23) to a persistent "## Human Guidance" log in the
  # doc, so it survives past the single run that consumes pending_guidance and
  # every later agent re-reading the doc still sees it.
  def append_guidance(task, guidance)
    existing = read(task)
    block = "## Human Guidance\n\n#{guidance.strip}\n"
    body = existing.include?("## Human Guidance") ? "#{existing.rstrip}\n\n#{guidance.strip}\n" : "#{existing.rstrip}\n\n#{block}"
    write(task, body.lstrip)
  end

  def delete(task)
    path = doc_path(task)
    FileUtils.rm_f(path)
  end

  def delete_archive(task)
    FileUtils.rm_rf(File.join(archive_root, "projects", task.project_id.to_s, "tasks", "task-#{task.id}"))
    delete(task)
  end
end
