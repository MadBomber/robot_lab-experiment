require "open3"

# Reads open GitHub issues for a project via `gh`, best-effort (a missing or
# unauthenticated `gh` should never break the Project or New Task page --
# same "never load-bearing" posture as PrStatusService). Shells out from
# project.effective_cwd so `gh` infers the repo from that directory's git
# remote, matching PrStatusService/WorktreeService's convention.
class GithubIssueService
  Issue = Data.define(:number, :title, :body, :url)

  def self.list(project)
    out, _err, status = Open3.capture3("gh", "issue", "list", "--state", "open",
                                       "--json", "number,title,url", chdir: project.effective_cwd)
    return [] unless status.success?

    JSON.parse(out).map { |i| Issue.new(number: i["number"], title: i["title"], body: nil, url: i["url"]) }
  rescue StandardError
    []
  end

  def self.find(project, number)
    out, _err, status = Open3.capture3("gh", "issue", "view", number.to_s,
                                       "--json", "number,title,body,url", chdir: project.effective_cwd)
    return nil unless status.success?

    i = JSON.parse(out)
    Issue.new(number: i["number"], title: i["title"], body: i["body"], url: i["url"])
  rescue StandardError
    nil
  end
end
