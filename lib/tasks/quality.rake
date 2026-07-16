# frozen_string_literal: true

# Complexity/duplication gates for `asgard quality`. Mirrors the sibling gems'
# Rakefile.common tasks of the same name, but scans app/**/*.rb -- this is a
# Rails app, not a gem, so its source lives under app/, not lib/.

FLOG_METHOD_WARN = 20.0
FLOG_METHOD_FAIL = 50.0
FLAY_MASS_THRESHOLD = 50

def flog_classify(flogger)
  scores = []
  flogger.each_by_score { |method, score| scores << [method, score] }

  scores.each_with_object(warnings: [], failures: []) do |(method, score), acc|
    next if method.end_with?("#none")

    entry = "#{format('%.1f', score)}: #{method}"
    acc[:failures] << entry if score > FLOG_METHOD_FAIL
    acc[:warnings] << entry if score > FLOG_METHOD_WARN && score <= FLOG_METHOD_FAIL
  end
end

desc "Check code complexity with Flog (warn >=20, fail >=50)"
task :flog_check do
  require "flog"

  flogger = Flog.new(all: true)
  flogger.flog(*Dir.glob("app/**/*.rb"))

  classified = flog_classify(flogger)

  unless classified[:warnings].empty?
    puts "\nFlog warnings (#{FLOG_METHOD_WARN}–#{FLOG_METHOD_FAIL}) -- target for future refactoring:"
    classified[:warnings].each { |v| puts "  #{v}" }
  end

  if classified[:failures].empty?
    puts "\nFlog: no methods exceed the failure threshold (>=#{FLOG_METHOD_FAIL})"
  else
    puts "\nFlog failures (>=#{FLOG_METHOD_FAIL}) -- must be refactored:"
    classified[:failures].each { |v| puts "  #{v}" }
    abort "\nFlog quality gate failed: #{classified[:failures].size} method(s) exceed #{FLOG_METHOD_FAIL}"
  end
end

desc "Check for structural code duplication with Flay (mass >= 50)"
task :flay_check do
  require "flay"

  flay = Flay.new({ mass: FLAY_MASS_THRESHOLD, diff: false, verbose: false, summary: false, timeout: 60 })
  flay.process(*Dir.glob("app/**/*.rb"))
  flay.analyze

  if flay.hashes.empty?
    puts "\nFlay: no structural duplication detected (mass >= #{FLAY_MASS_THRESHOLD})"
  else
    puts "\nFlay found structural duplication (mass >= #{FLAY_MASS_THRESHOLD}):"
    flay.report
    abort "\nFlay quality gate failed: #{flay.hashes.length} pattern(s) detected"
  end
end
