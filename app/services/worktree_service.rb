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
    return if @task.worktree_path.blank?

    run("git", "worktree", "remove", "--force", @task.worktree_path, chdir: @project.repo_folder_path)
    run("git", "branch", "-D", @task.branch_name, chdir: @project.repo_folder_path) if @task.branch_name.present?
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
