require "open3"

# Reads open GitHub issues for a project via `gh`, best-effort (a missing or
# unauthenticated `gh` should never break the Project or New Task page --
# same "never load-bearing" posture as PrStatusService). Shells out from
# project.effective_cwd so `gh` infers the repo from that directory's git
# remote, matching PrStatusService/WorktreeService's convention.
class GithubIssueService
  Comment = Data.define(:author, :body, :created_at) do
    def attributed_text
      "--- Comment from #{author} (#{created_at}) ---\n\n#{body.to_s.strip}"
    end
  end

  Issue = Data.define(:number, :title, :body, :url, :comments) do
    def initialize(comments: [], **rest) = super

    # The whole issue thread as one prompt-ready block: the body plus every
    # comment, attributed -- so a task seeded from an issue carries the full
    # discussion (triage notes, confirmed diagnoses, suggested fixes), not
    # just the original complaint.
    def thread_text
      [body.to_s.strip, *comments.map(&:attributed_text)].reject(&:empty?).join("\n\n")
    end
  end

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
                                       "--json", "number,title,body,url,comments", chdir: project.effective_cwd)
    return nil unless status.success?

    i = JSON.parse(out)
    Issue.new(number: i["number"], title: i["title"], body: i["body"], url: i["url"],
              comments: parse_comments(i["comments"]))
  rescue StandardError
    nil
  end

  # gh's comments JSON: [{"author":{"login":...},"body":...,"createdAt":...}]
  def self.parse_comments(raw)
    raw.to_a.map do |comment|
      Comment.new(author: comment.dig("author", "login"), body: comment["body"],
                  created_at: comment["createdAt"])
    end
  end
  private_class_method :parse_comments
end
