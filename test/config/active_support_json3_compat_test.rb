require "test_helper"

# Guards the json 3.x backport in
# config/initializers/active_support_json3_compat.rb: json 3 made JSON.parse
# options keyword-only, and activesupport <= 8.1.3.1 passes a positional hash.
# Once Rails > 8.1.3.1 is in the bundle, the initializer (and this test) can
# be deleted.
class ActiveSupportJson3CompatTest < ActiveSupport::TestCase
  test "bundle uses json 3.x" do
    assert_operator Gem::Version.new(JSON::VERSION), :>=, Gem::Version.new("3.0.0")
  end

  test "decode without options parses JSON" do
    assert_equal({ "team" => "rails" }, ActiveSupport::JSON.decode(%({"team":"rails"})))
  end

  test "decode with options forwards them as keywords" do
    assert_equal({ team: "rails" }, ActiveSupport::JSON.decode(%({"team":"rails"}), symbolize_names: true))
  end

  # ActiveRecord::Coders::JSON#load passes { escape: false } -- an
  # encoder-only option json 2.x ignored but json 3 rejects as an unknown
  # keyword. The backport must slice it away or every serialized-attribute
  # load (e.g. Solid Queue registering its worker process) crashes at boot.
  test "decode ignores encoder-only options the way json 2.x did" do
    assert_equal({ "team" => "rails" }, ActiveSupport::JSON.decode(%({"team":"rails"}), escape: false))
  end

  test "decode with mixed options keeps the parse options and drops the rest" do
    assert_equal({ team: "rails" },
                 ActiveSupport::JSON.decode(%({"team":"rails"}), escape: false, symbolize_names: true))
  end

  test "load stays aliased to decode" do
    assert_equal [1, 2], ActiveSupport::JSON.load("[1,2]")
  end

  test "decode still raises the advertised parse error on bad input" do
    assert_raises(ActiveSupport::JSON.parse_error) { ActiveSupport::JSON.decode("{nope") }
  end
end
