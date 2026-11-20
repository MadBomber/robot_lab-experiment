class GrepTool < CodingTool
  MAX_MATCHES = 200

  description "Search file contents for a regular expression within the working directory."
  parameter :pattern, type: "string", description: "Ruby-compatible regular expression to search for."
  parameter :path, type: "string", description: "Subdirectory to search within, relative to the working directory.", required: false
  parameter :glob, type: "string", description: "Only search files matching this glob (e.g. '*.rb').", required: false

  def execute(pattern:, path: ".", glob: "**/*")
    base = resolve_read_path(path)
    raise RobotLab::ToolError, "no such directory: #{path}" unless File.directory?(base)

    matches = search(base, compile(pattern), glob)
    matches.empty? ? "No matches" : matches.join("\n")
  end

  private

  def compile(pattern)
    Regexp.new(pattern)
  rescue RegexpError => e
    raise RobotLab::ToolError, "invalid pattern: #{e.message}"
  end

  # Matching lines ("path:lineno:line") across every readable file under base,
  # capped at MAX_MATCHES. Lazy so the file walk stops once the cap is hit.
  def search(base, regexp, glob)
    Dir.glob(File.join(base, glob))
       .lazy
       .select { |f| File.file?(f) && read_scoped?(f) }
       .flat_map { |file| grep_file(file, regexp, MAX_MATCHES) }
       .first(MAX_MATCHES)
  end

  # This one file's matching lines, at most limit of them. Lazy so a huge
  # file stops being read once its limit is hit.
  def grep_file(file, regexp, limit)
    File.foreach(file)
        .with_index(1)
        .lazy
        .select { |line, _lineno| regexp.match?(line) }
        .first(limit)
        .map { |line, lineno| "#{file.delete_prefix("#{cwd}/")}:#{lineno}:#{line.chomp}" }
  rescue ArgumentError
    [] # binary file, skip
  end
end
