require "test_helper"
require "open3"

class QualityGateToolTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir("quality_gate_tool_test")
    @tool = QualityGateTool.new(cwd: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  test "skips everything with no Gemfile in the working directory" do
    # Dir.mktmpdir lives outside this repo's tree, so Bundler's upward search
    # for a Gemfile genuinely finds nothing here -- no stubbing needed.
    result = @tool.execute
    assert_equal "No Gemfile/bundle found in this repo -- skipping all Ruby quality gates.", result
  end

  test "skips a gated check whose gem isn't in the bundle" do
    stub_bundled(%w[rubocop]) do
      stub_commands({}) do
        result = @tool.execute
        assert_includes result, "SKIP Bundler Audit (gem 'bundler-audit' not in this repo's Gemfile)"
      end
    end
  end

  test "skips rails-only checks when the target isn't a Rails app" do
    stub_bundled(%w[rubocop brakeman rails_best_practices active_record_doctor bundler-audit]) do
      stub_commands({}) do
        result = @tool.execute
        assert_includes result, "SKIP Brakeman (not a Rails app)"
        assert_includes result, "SKIP RailsBestPractices (not a Rails app)"
        assert_includes result, "SKIP ActiveRecordDoctor (not a Rails app)"
      end
    end
  end

  test "runs rails-only checks when config/application.rb exists and rails is bundled" do
    FileUtils.mkdir_p(File.join(@dir, "config"))
    File.write(File.join(@dir, "config/application.rb"), "")

    stub_bundled(%w[rails brakeman]) do
      stub_commands({ "bundle exec brakeman -q --no-progress" => ["", success] }) do
        result = @tool.execute
        assert_includes result, "PASS Brakeman"
      end
    end
  end

  test "reports a gated check's output on failure" do
    stub_bundled(%w[rubocop]) do
      stub_commands({ "bundle exec rubocop" => ["app/foo.rb:1: offense", failure] }) do
        result = @tool.execute
        assert_includes result, "FAIL RuboCop"
        assert_includes result, "app/foo.rb:1: offense"
        assert_includes result, "Overall: FAIL"
      end
    end
  end

  test "points bundle-audit at a non-standard lockfile when Gemfile.lock is absent" do
    File.write(File.join(@dir, "Gemfile.local.lock"), "")

    stub_bundled(%w[bundler-audit]) do
      stub_commands({ "bundle exec bundle-audit check --update --gemfile_lock Gemfile.local.lock" => ["", success] }) do
        result = @tool.execute
        assert_includes result, "PASS Bundler Audit"
      end
    end
  end

  test "flog reports methods at or above the fail threshold as a failure" do
    FileUtils.mkdir_p(File.join(@dir, "app"))
    output = <<~FLOG
      75.5: flog total
      37.7: flog/method average
      60.0: Foo#bar          app/foo.rb:1-3
      25.0: Foo#baz          app/foo.rb:5-7
    FLOG

    stub_bundled(%w[flog]) do
      stub_commands({ "bundle exec flog -a app" => [output, success] }) do
        result = @tool.execute
        assert_includes result, "FAIL"
        assert_includes result, "60.0: Foo#bar"
        assert_includes result, "WARN 25.0: Foo#baz"
      end
    end
  end

  test "flay reports duplication at or above the fail mass as a failure" do
    FileUtils.mkdir_p(File.join(@dir, "app"))
    output = <<~FLAY
      Total score (lower is better) = 200
        1) Similar code found in :defn (mass = 200)
    FLAY

    stub_bundled(%w[flay]) do
      stub_commands({ "bundle exec flay app" => [output, success] }) do
        result = @tool.execute
        assert_includes result, "FAIL 1 duplication pattern(s) at or above 150 (mass: 200)"
      end
    end
  end

  test "reek is reported as informational and never fails the overall verdict" do
    FileUtils.mkdir_p(File.join(@dir, "app"))
    stub_bundled(%w[rubocop reek]) do
      stub_commands({
        "bundle exec rubocop" => ["", success],
        "bundle exec reek app" => ["app/foo.rb -- 1 warning:\n  smell", failure]
      }) do
        result = @tool.execute
        assert_includes result, "Overall: PASS"
        assert_includes result, "Reek (informational -- not a pass/fail gate)"
        assert_includes result, "smell"
      end
    end
  end

  private

  def success
    Struct.new(:success?).new(true)
  end

  def failure
    Struct.new(:success?).new(false)
  end

  # Stubs the one `bundle list --name-only` call every execute() makes.
  def stub_bundled(names, &)
    Open3.stub(:capture2e, ["#{names.join("\n")}\n", success], &)
  end

  # Stubs every `bundle exec ...` invocation made via QualityGateTool#run.
  # command_map: exact command string => [output, status]. Anything not in
  # the map returns empty output with a successful status.
  def stub_commands(command_map, &block)
    fake_popen2e = lambda do |_env, command, **_kwargs, &block|
      output, status = command_map.fetch(command, ["", success])
      stdin = Object.new.tap { |o| o.define_singleton_method(:close) {} }
      wait = Object.new.tap { |o| o.define_singleton_method(:value) { status } }
      block.call(stdin, StringIO.new(output), wait)
    end

    Open3.stub(:popen2e, fake_popen2e, &block)
  end
end
