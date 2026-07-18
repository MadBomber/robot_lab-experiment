class GrepTool < CodingTool
  MAX_MATCHES = 200

  description "Search file contents for a regular expression within the working directory."
  param :pattern, type: "string", desc: "Ruby-compatible regular expression to search for."
  param :path, type: "string", desc: "Subdirectory to search within, relative to the working directory.", required: false
  param :glob, type: "string", desc: "Only search files matching this glob (e.g. '*.rb').", required: false

  def execute(pattern:, path: ".", glob: "**/*")
    base = resolve_read_path(path)
    raise RobotLab::ToolError, "no such directory: #{path}" unless File.directory?(base)

    regexp = compile(pattern)
    matches = []

    Dir.glob(File.join(base, glob)).each do |file|
      next unless File.file?(file)

      grep_file(file, regexp, matches)
      break if matches.size >= MAX_MATCHES
    end

    matches.empty? ? "No matches" : matches.first(MAX_MATCHES).join("\n")
  end

  private

  def compile(pattern)
    Regexp.new(pattern)
  rescue RegexpError => e
    raise RobotLab::ToolError, "invalid pattern: #{e.message}"
  end

  def grep_file(file, regexp, matches)
    File.foreach(file).with_index(1) do |line, lineno|
      next unless regexp.match?(line)

      matches << "#{file.delete_prefix("#{cwd}/")}:#{lineno}:#{line.chomp}"
      break if matches.size >= MAX_MATCHES
    end
  rescue ArgumentError
    nil # binary file, skip
  end
end
