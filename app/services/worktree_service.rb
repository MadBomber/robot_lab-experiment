require "open3"

# Wraps `git worktree` so each Task gets an isolated workspace: a sibling
# directory (never inside the main checkout) on its own branch. Concurrent
# tasks never collide on the filesystem, and the main checkout stays untouched.
#
# All git invocations go through Open3.capture3 with an argv array -- no shell
# interpolation, matching robot_lab-to's CommitManager convention.
class WorktreeService
  class Error < StandardError; end

  def initialize(task)
    @task = task
    @project = task.project
  end

  def create
    branch = branch_name
    path = worktree_path

    run!("git", "worktree", "add", "-b", branch, path, default_branch, chdir: @project.repo_folder_path)

    @task.update!(branch_name: branch, worktree_path: path)
    path
  end

  def remove
    return unless @task.worktree_path?

    _out, err, status = run("git", "worktree", "remove", "--force", @task.worktree_path, chdir: @project.repo_folder_path)
    # git errors if the worktree is already gone -- that's a no-op success for us.
    # But a real failure that leaves the directory behind (permissions, locked
    # files, corrupt state) must surface, not be swallowed into a false success.
    raise Error, "git worktree remove failed: #{err.strip}" if !status.success? && Dir.exist?(@task.worktree_path)

    # Branch deletion stays best-effort: a missing branch (already deleted, or
    # never created) is a normal, benign state and must not block teardown.
    run("git", "branch", "-D", @task.branch_name, chdir: @project.repo_folder_path) if @task.branch_name?
  end

  private

  def branch_name
    "task/#{@task.id}-#{sanitized_title}"
  end

  def sanitized_title
    @task.title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "").slice(0, 50).presence || "untitled"
  end

  def worktree_path
    "#{@project.repo_folder_path.chomp("/")}-worktrees/task-#{@task.id}"
  end

  def default_branch
    out, _err, status = Open3.capture3("git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD",
                                       chdir: @project.repo_folder_path)
    return out.strip.sub(%r{\Aorigin/}, "") if status.success? && out.present?

    out, _err, status = Open3.capture3("git", "symbolic-ref", "--short", "HEAD", chdir: @project.repo_folder_path)
    return out.strip if status.success? && out.present?

    "main"
  end

  def run!(*argv, chdir:)
    _out, err, status = Open3.capture3(*argv, chdir: chdir)
    raise Error, "#{argv.join(' ')} failed: #{err}" unless status.success?
  end

  def run(*argv, chdir:)
    Open3.capture3(*argv, chdir: chdir)
  end
end
