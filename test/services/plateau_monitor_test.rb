require "test_helper"

class PlateauMonitorTest < ActiveSupport::TestCase
  Call = Struct.new(:name, :arguments)

  def setup
    @monitor = PlateauMonitor.new
  end

  test "tolerates varied tool calls without tripping" do
    assert_nothing_raised do
      10.times { |i| @monitor.record_tool_call(Call.new("bash", { command: "echo #{i}" })) }
    end
  end

  test "trips when the identical (tool, args) call repeats past the limit" do
    call = Call.new("bash", { command: "gh run view 123" })
    (PlateauMonitor::IDENTICAL_CALL_LIMIT - 1).times { @monitor.record_tool_call(call) }

    error = assert_raises(PlateauMonitor::Plateaued) { @monitor.record_tool_call(call) }
    assert_match "repeated the same tool call", error.message
  end

  test "a differing call resets the consecutive-identical counter" do
    same = Call.new("bash", { command: "make test" })
    assert_nothing_raised do
      (PlateauMonitor::IDENTICAL_CALL_LIMIT - 1).times { @monitor.record_tool_call(same) }
      @monitor.record_tool_call(Call.new("bash", { command: "make lint" }))
      (PlateauMonitor::IDENTICAL_CALL_LIMIT - 1).times { @monitor.record_tool_call(same) }
    end
  end

  test "trips when the identical result recurs consecutively past the limit" do
    (PlateauMonitor::IDENTICAL_RESULT_LIMIT - 1).times { @monitor.record_tool_result("same error") }

    error = assert_raises(PlateauMonitor::Plateaued) { @monitor.record_tool_result("same error") }
    assert_match "same tool result recurred", error.message
  end

  test "a differing result between repeats resets the streak (edit/test debug loop)" do
    # The Task 28 false positive: the same test failure recurs, but the agent
    # makes an edit (a different result) between each run -- real iteration.
    assert_nothing_raised do
      (PlateauMonitor::IDENTICAL_RESULT_LIMIT * 3).times do
        @monitor.record_tool_result("test failure: SyntaxError")
        @monitor.record_tool_result("Replaced 1 occurrence(s)")
      end
    end
  end

  test "trips at the absolute tool-call ceiling even when calls vary" do
    error = assert_raises(PlateauMonitor::Plateaued) do
      (PlateauMonitor::MAX_TOOL_CALLS + 1).times { |i| @monitor.record_tool_call(Call.new("read", { path: "f#{i}" })) }
    end
    assert_match "tool calls in one run", error.message
  end
end
