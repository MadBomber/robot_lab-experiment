require "open3"
require "timeout"

# Runs a battery of Ruby/Rails quality checks against the working directory
# and returns a structured pass/fail/skip report -- the review agent's
# equivalent of `asgard quality` (see ~/sandbox/git_repos/madbomber/dev/quality.loki
# and quality_rails.loki), ported natively rather than shelled out to the
# `asgard` gem. Two reasons it's ported instead of just calling `asgard`:
# asgard resolves its check list via `import_up "dev/*.loki"`, which only
# reaches repos that live under that specific workspace tree -- this tool
# has to work on *any* repo a Project points at, wherever it lives on disk.
# And asgard itself just runs `bundle exec <tool>` under the hood for every
# check -- there's no dependency to replicate beyond doing the same thing
# directly via Open3, the same way BashTool does.
#
# Every check is `bundle exec <cli>` in the target repo's own bundle -- this
# tool needs none of these gems in robot_lab-experiment's own Gemfile. A
# check is SKIPPED (not failed) when its gem isn't in the target's bundle,
# or when it's Rails-only and the target isn't a Rails app.
class QualityGateTool < CodingTool
  TIMEOUT = 300

  # name / gem: the bundled gem name to check for before running.
  # command: run relative to cwd via `bundle exec`.
  # rails_only: only attempted when the target repo is a Rails app.
  # gate: true -- a non-zero exit is a real FAIL. false -- always informational,
  # exit status is not treated as a gate.
  GATED_CHECKS = [
    { name: "RuboCop", gem: "rubocop", command: "bundle exec rubocop", gate: true },
    { name: "Bundler Audit", gem: "bundler-audit", command: :bundler_audit_command, gate: true },
    { name: "Brakeman", gem: "brakeman", command: "bundle exec brakeman -q --no-progress", gate: true, rails_only: true },
    { name: "RailsBestPractices", gem: "rails_best_practices",
      command: "bundle exec rails_best_practices --silent --without-color .", gate: true, rails_only: true },
    { name: "ActiveRecordDoctor", gem: "active_record_doctor", command: "bundle exec rake active_record_doctor",
      gate: true, rails_only: true }
  ].freeze

  INFO_CHECKS = [
    { name: "Reek", gem: "reek", command: "bundle exec reek %<dirs>s" }
  ].freeze

  # Per-method score thresholds, same as asgard's flog_check/flay_check.
  FLOG_METHOD_WARN = 20.0
  FLOG_METHOD_FAIL = 50.0
  FLAY_MASS_FAIL = 150

  description "Run this repo's Ruby/Rails quality gates (RuboCop, Brakeman, Bundler Audit, " \
              "RailsBestPractices, ActiveRecordDoctor, Flog, Flay, Reek) and return a pass/fail/skip " \
              "report. Rails-only checks and any check whose gem isn't in this repo's Gemfile are " \
              "skipped automatically -- this is safe to call on any Ruby repo, Rails or not. " \
              "Takes no parameters and always runs the full battery."

  def execute
    bundled = bundled_gems
    rails = rails_app?(bundled)

    sections = []
    sections << gated_report(bundled, rails)
    sections << flog_report(bundled)
    sections << flay_report(bundled)
    sections << info_report(bundled)

    sections.compact.join("\n\n")
  end

  private

  def bundled_gems
    out, status = Open3.capture2e(bundle_env, "bundle list --name-only", chdir: cwd)
    return nil unless status.success?

    out.lines.to_set(&:strip)
  rescue StandardError
    nil
  end

  # A subprocess started with the current env would inherit whatever Bundler
  # context this Rails process itself is running under (e.g. this app's own
  # Gemfile.local via direnv) regardless of `chdir:` -- wrong for a different
  # target repo. Blindly clearing BUNDLE_GEMFILE instead would be just as
  # wrong for a target repo that itself needs a non-default Gemfile (this
  # app included -- it only boots via Gemfile.local, which eval_gemfiles the
  # plain Gemfile; a plain "Gemfile exists" check isn't enough to tell the
  # two apart). So: point BUNDLE_GEMFILE at cwd's own Gemfile.local when one
  # exists, otherwise clear it so Bundler's normal upward search from cwd
  # finds cwd's own plain Gemfile instead of whatever this process inherited.
  def bundle_env
    local_gemfile = File.join(cwd, "Gemfile.local")
    { "BUNDLE_GEMFILE" => (File.exist?(local_gemfile) ? local_gemfile : nil),
      "BUNDLE_BIN_PATH" => nil, "RUBYOPT" => nil }
  end

  def rails_app?(bundled)
    return false if bundled.nil?

    bundled.include?("rails") && File.exist?(File.join(cwd, "config", "application.rb"))
  end

  def gated_report(bundled, rails)
    return "No Gemfile/bundle found in this repo -- skipping all Ruby quality gates." if bundled.nil?

    lines = ["## Quality gates"]
    failed = false

    GATED_CHECKS.each do |check|
      if check[:rails_only] && !rails
        lines << "- SKIP #{check[:name]} (not a Rails app)"
        next
      end
      unless bundled.include?(check[:gem])
        lines << "- SKIP #{check[:name]} (gem '#{check[:gem]}' not in this repo's Gemfile)"
        next
      end

      command = check[:command].is_a?(Symbol) ? send(check[:command]) : check[:command]
      output, status = run(command)
      if status&.success?
        lines << "- PASS #{check[:name]}"
      else
        failed = true
        lines << "- FAIL #{check[:name]}\n#{indent(truncate(output))}"
      end
    end

    lines << "\nOverall: #{failed ? 'FAIL -- see the FAIL sections above' : 'PASS'}"
    lines.join("\n")
  end

  # bundle-audit hardcodes a look for a file literally named "Gemfile.lock" in
  # cwd, ignoring BUNDLE_GEMFILE -- several repos in this workspace (this app
  # included) bundle via a differently-named Gemfile (e.g. Gemfile.local),
  # so their lockfile is Gemfile.local.lock instead. Point bundle-audit at
  # whichever *Gemfile*.lock actually exists when the plain default isn't there.
  def bundler_audit_command
    return "bundle exec bundle-audit check --update" if File.exist?(File.join(cwd, "Gemfile.lock"))

    lockfile = Dir.glob(File.join(cwd, "*Gemfile*.lock")).map { |f| File.basename(f) }.min
    return "bundle exec bundle-audit check --update" unless lockfile

    "bundle exec bundle-audit check --update --gemfile_lock #{lockfile}"
  end

  def flog_report(bundled)
    dirs = code_dirs
    return nil if bundled.nil? || dirs.empty? || !bundled.include?("flog")

    output, status = run("bundle exec flog -a #{dirs.join(' ')}")
    return "## Flog Complexity\n- SKIP (flog did not run: #{truncate(output)})" unless status&.success?

    scores = output.each_line.filter_map { |l| l.match(/^\s*([\d.]+):\s+(.+)$/) }
                   .drop(2) # first two lines are the total and per-method average
                   .map { |m| [m[1].to_f, m[2].strip] }
    failures = scores.select { |score, _| score >= FLOG_METHOD_FAIL }
    warnings = scores.select { |score, _| score >= FLOG_METHOD_WARN && score < FLOG_METHOD_FAIL }

    lines = ["## Flog Complexity (fail >= #{FLOG_METHOD_FAIL}, warn >= #{FLOG_METHOD_WARN})"]
    lines << (failures.empty? ? "- PASS no method at or above #{FLOG_METHOD_FAIL}" : "- FAIL:")
    failures.each { |score, method| lines << "    #{score}: #{method}" }
    warnings.each { |score, method| lines << "  - WARN #{score}: #{method}" }
    lines.join("\n")
  end

  def flay_report(bundled)
    dirs = code_dirs
    return nil if bundled.nil? || dirs.empty? || !bundled.include?("flay")

    output, status = run("bundle exec flay #{dirs.join(' ')}")
    return "## Flay Duplication\n- SKIP (flay did not run: #{truncate(output)})" unless status&.success?

    masses = output.each_line.filter_map { |l| l[/mass = (\d+)/, 1]&.to_i }
    failures = masses.select { |m| m >= FLAY_MASS_FAIL }

    lines = ["## Flay Duplication (fail mass >= #{FLAY_MASS_FAIL})"]
    lines << if failures.empty?
               "- PASS #{masses.size} duplication pattern(s) found, none at or above #{FLAY_MASS_FAIL}"
             else
               "- FAIL #{failures.size} duplication pattern(s) at or above #{FLAY_MASS_FAIL} (mass: #{failures.join(', ')})"
             end
    lines.join("\n")
  end

  def info_report(bundled)
    return nil if bundled.nil?

    dirs = code_dirs
    sections = INFO_CHECKS.filter_map do |check|
      next unless bundled.include?(check[:gem])
      next if dirs.empty?

      output, status = run(format(check[:command], dirs: dirs.join(" ")))
      summary = status&.success? ? "no findings" : truncate(output)
      "## #{check[:name]} (informational -- not a pass/fail gate)\n#{indent(summary)}"
    end

    sections.empty? ? nil : sections.join("\n\n")
  end

  def code_dirs
    %w[app lib].select { |d| File.directory?(File.join(cwd, d)) }
  end

  def run(command)
    output = +""
    Open3.popen2e(bundle_env, command, chdir: cwd, pgroup: true) do |stdin, out, wait|
      stdin.close
      Timeout.timeout(TIMEOUT) { output << out.read }
      return [output, wait.value]
    end
  rescue Timeout::Error
    [output + "\n[killed: exceeded #{TIMEOUT}s]", nil]
  end

  def truncate(text, limit: 4000)
    text.length > limit ? "#{text[0, limit]}\n... [truncated]" : text
  end

  def indent(text)
    text.to_s.each_line.map { |l| "  #{l}" }.join
  end
end
