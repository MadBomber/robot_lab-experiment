# Code coverage is opt-in (COVERAGE=1) so the normal parallel test run stays
# fast. SimpleCov only *measures* here (writing coverage/.last_run.json); the
# 90% gate itself is owned and displayed by `asgard quality` (see .loki), so the
# threshold lives in one place. Must start before any app code is required.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/test/"
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Under coverage, run single-process for a simple, accurate measurement (no
    # cross-worker merging); otherwise parallelize across cores for speed.
    parallelize(workers: ENV["COVERAGE"] ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Throwaway git repo in a tmpdir — bare `git init`, no commits. Enough for
    # tests that only need the repo to *validate*; call commit_git_scaffold
    # when a HEAD is required (e.g. before `git worktree add`).
    def init_git_repo(prefix = "test_repo")
      dir = Dir.mktmpdir(prefix)
      git! dir, "init", "--quiet"
      dir
    end

    # Gives the repo an identity and an initial commit. Identity, signing, and
    # hooks are pinned per-repo so the outcome never depends on the developer's
    # global git config (commit.gpgsign without a usable key exits 128;
    # core.hooksPath/init templates can inject failing hooks).
    def commit_git_scaffold(dir)
      git! dir, "config", "user.email", "test@example.com"
      git! dir, "config", "user.name", "Test User"
      git! dir, "config", "commit.gpgsign", "false"
      git! dir, "config", "core.hooksPath", File::NULL
      File.write(File.join(dir, "README.md"), "hello")
      git! dir, "add", "."
      git! dir, "commit", "--quiet", "-m", "initial"
      dir
    end

    # Runs git in dir, raising on spawn failure or non-zero exit so a broken
    # scaffold fails at the point of breakage instead of as a downstream assert.
    def git!(dir, *)
      system("git", "-C", dir, *, exception: true)
    end
  end
end
