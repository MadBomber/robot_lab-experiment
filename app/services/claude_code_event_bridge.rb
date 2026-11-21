# Feeds Claude Code's tool activity into the same oversight a RubyLLM run
# gets from robot_lab's on_tool_call/on_tool_result callbacks. The
# claude_code provider never fires those callbacks (the agent runs its own
# tools), but it hands every parsed stream-json event to its on_event hook,
# and this object is that hook:
#
# - an assistant event's tool_use blocks are recorded in the transcript and
#   in the PlateauMonitor, after a check for a requested Stop/Abandon;
# - a user event's tool_result blocks are recorded the same way.
#
# A raise from here (Cancelled, PlateauMonitor::Plateaued) kills the claude
# process and unwinds AgentRunJob#run_turn exactly as it would for a RubyLLM
# run. Subagent events (parent_tool_use_id set) are recorded too, so the
# monitor's ceiling covers the whole run.
class ClaudeCodeEventBridge
  # The shape TranscriptRecorder and PlateauMonitor read from a tool call.
  ToolCall = Data.define(:id, :name, :arguments)

  # @param recorder [TranscriptRecorder]
  # @param monitor [PlateauMonitor]
  # @param cancel_requested [#call] true once a human has asked to stop the run
  def initialize(recorder:, monitor:, cancel_requested:)
    @recorder = recorder
    @monitor = monitor
    @cancel_requested = cancel_requested
  end

  def call(event)
    case event["type"]
    when "assistant" then blocks(event, "tool_use").each { |block| tool_use(block) }
    when "user" then blocks(event, "tool_result").each { |block| tool_result(block) }
    end
  end

  # A tool_result's content is a string or a list of content blocks; the
  # transcript and the monitor want the text.
  def self.result_text(content)
    return content.to_s unless content.is_a?(Array)

    content.map { |part| part.is_a?(Hash) ? part["text"].to_s : part.to_s }.join("\n")
  end

  private

  def blocks(event, type)
    content = event.dig("message", "content")
    return [] unless content.is_a?(Array)

    content.select { |block| block.is_a?(Hash) && block["type"] == type }
  end

  def tool_use(block)
    call = ToolCall.new(id: block["id"], name: block["name"], arguments: block["input"] || {})
    @recorder.record_tool_call(call)
    raise AgentRunJob::Cancelled if @cancel_requested.call

    @monitor.record_tool_call(call)
  end

  def tool_result(block)
    text = self.class.result_text(block["content"])
    @recorder.record_tool_result(text, tool_use_id: block["tool_use_id"])
    @monitor.record_tool_result(text)
  end
end
