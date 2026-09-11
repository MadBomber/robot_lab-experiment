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

    path = @task.worktree_path
    _out, err, status = run("git", "worktree", "remove", "--force", path, chdir: @project.repo_folder_path)
    # git errors if the worktree is already gone -- that's a no-op success for us.
    if !status.success? && Dir.exist?(path)
      # A real failure that leaves the directory behind (permissions, locked
      # files, corrupt state) must surface, not be swallowed into a false success.
      raise Error, "git worktree remove failed: #{err.strip}" unless err.include?("is not a working tree")

      # git has no administrative record of this as a worktree at all (e.g.
      # pruned separately, or the .git/worktrees/<name> entry is otherwise
      # gone) -- there's nothing left for git to manage, so remove the
      # orphaned directory ourselves rather than leaving it stuck forever.
      FileUtils.rm_rf(path)
    end

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
    remote_head = symbolic_ref("refs/remotes/origin/HEAD")
    return remote_head.sub(%r{\Aorigin/}, "") if remote_head

    main_worktree_head || "main"
  end

  # HEAD of the repository's *main* worktree. A bare `symbolic-ref HEAD` run
  # from a linked worktree answers with that worktree's own checked-out
  # branch — not a repository default — so resolve through --git-common-dir,
  # which pins the answer to the main checkout no matter which worktree
  # repo_folder_path points at (for a normal checkout it's the same .git).
  def main_worktree_head
    common_dir = run_for_stdout("git", "rev-parse", "--path-format=absolute", "--git-common-dir",
                                chdir: @project.repo_folder_path)
    return unless common_dir

    run_for_stdout("git", "--git-dir", common_dir, "symbolic-ref", "--short", "HEAD",
                   chdir: @project.repo_folder_path)
  end

  # The short name `git symbolic-ref` resolves for ref, or nil when the ref
  # doesn't resolve (e.g. no origin/HEAD in a local-only repo).
  def symbolic_ref(ref)
    run_for_stdout("git", "symbolic-ref", "--short", ref, chdir: @project.repo_folder_path)
  end

  def run!(*argv, chdir:)
    _out, err, status = Open3.capture3(*argv, chdir: chdir)
    raise Error, "#{argv.join(' ')} failed: #{err}" unless status.success?
  end

  def run(*argv, chdir:)
    Open3.capture3(*argv, chdir: chdir)
  end

  # Stripped stdout when the command succeeds, nil when it fails or prints
  # nothing -- for callers that treat failure as "no answer".
  def run_for_stdout(*argv, chdir:)
    out, _err, status = run(*argv, chdir: chdir)
    out.strip.presence if status.success?
  end
end
