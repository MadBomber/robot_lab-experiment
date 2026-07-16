require "open3"

# Best-effort hint for the PR agent's prompt -- never load-bearing. The PR
# agent does the real work (create-or-verify, CI polling, conflicts) itself
# via the shell tool; this only saves it one round trip to check.
class PrStatusService
  def self.call(task)
    new(task).call
  end

  def initialize(task)
    @task = task
  end

  def call
    return "No branch yet." unless @task.branch_name?

    out, _err, status = Open3.capture3("gh", "pr", "view", @task.branch_name, "--json", "url,state",
                                       chdir: @task.effective_cwd)
    return "No pull request open yet for branch #{@task.branch_name}." unless status.success?

    data = JSON.parse(out)
    "PR already exists: #{data['url']} (state: #{data['state']})."
  rescue StandardError
    "No pull request open yet for branch #{@task.branch_name}."
  end
end
