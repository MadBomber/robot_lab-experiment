require "digest"

# Within-run plateau detection: watches a single agent run's tool activity and
# raises Plateaued the moment the run stops making forward progress, so a stuck
# run is killed after a handful of wasted calls instead of hundreds.
#
# This is the app-level hard stop robot_lab's own DoomLoopDetector doesn't give
# us: that only tracks tool *names* and injects a soft warning the LLM can (and
# did, for 172 calls) ignore. Here we key on the tool call's *arguments* and on
# the *result*, so "run the tests 3 times" (progress) is distinguished from
# "poll the same failing command forever" (a plateau), and we stop rather than
# nudge. robot_lab's max_tool_rounds circuit breaker is the coarser backstop.
#
# Fed from AgentRunJob's on_tool_call / on_tool_result callbacks, which robot_lab
# invokes synchronously inside robot.run -- so a raise here unwinds the run.
class PlateauMonitor
  class Plateaued < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("run plateaued: #{reason}")
    end
  end

  # Same (tool, args) this many times in a row -> stuck repeating one action.
  IDENTICAL_CALL_LIMIT = 4
  # Same result payload this many times total -> making calls but nothing changes.
  IDENTICAL_RESULT_LIMIT = 5
  # Absolute ceiling on tool calls in a single run, regardless of variety.
  MAX_TOOL_CALLS = 50

  def initialize(identical_call_limit: IDENTICAL_CALL_LIMIT,
                 identical_result_limit: IDENTICAL_RESULT_LIMIT,
                 max_tool_calls: MAX_TOOL_CALLS)
    @identical_call_limit = identical_call_limit
    @identical_result_limit = identical_result_limit
    @max_tool_calls = max_tool_calls
    @total_calls = 0
    @last_call_fingerprint = nil
    @consecutive_identical_calls = 0
    @result_counts = Hash.new(0)
  end

  # Raises Plateaued when the run has exceeded the total-call ceiling or is
  # repeating the identical (tool, arguments) call with no variation.
  def record_tool_call(tool_call)
    @total_calls += 1
    raise Plateaued, "exceeded #{@max_tool_calls} tool calls in one run" if @total_calls > @max_tool_calls

    fingerprint = call_fingerprint(tool_call)
    if fingerprint == @last_call_fingerprint
      @consecutive_identical_calls += 1
    else
      @last_call_fingerprint = fingerprint
      @consecutive_identical_calls = 1
    end

    return if @consecutive_identical_calls < @identical_call_limit

    raise Plateaued, "repeated the same tool call #{@consecutive_identical_calls} times"
  end

  # Raises Plateaued when one identical result (e.g. the same error) keeps coming
  # back -- calls may vary superficially but the world isn't changing.
  def record_tool_result(result)
    key = Digest::SHA256.hexdigest(result.to_s)
    count = (@result_counts[key] += 1)
    return if count < @identical_result_limit

    raise Plateaued, "the same tool result recurred #{count} times"
  end

  private

  def call_fingerprint(tool_call)
    name = tool_call.respond_to?(:name) ? tool_call.name : tool_call[:name]
    args = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call[:arguments]
    Digest::SHA256.hexdigest("#{name}\0#{args.inspect}")
  end
end
