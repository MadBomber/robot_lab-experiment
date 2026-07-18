require "securerandom"

# Persists a conversation's streaming output as idempotent, ordered Message
# rows, and broadcasts a live transcript view over Turbo Streams. One
# instance per AgentRunJob#perform call -- not safe to share across runs.
#
# Streaming chunks from RubyLLM carry DELTAS, not the running total (see
# RubyLLM::StreamAccumulator, which does the same `<<` accumulation
# internally) -- so content/thinking text is buffered here and flushed as one
# message per contiguous run, instead of persisting+broadcasting a new row
# per token. Thinking is flushed into the transcript for later review but
# never broadcast live -- a spinner (see #start/#finish) is the only live
# indicator while an agent is thinking or acting.
#
# Tool call/result pairing assumes sequential tool execution (the default);
# if robot_lab ever enables ruby_llm's concurrent tool execution, this naive
# "last tool_call wins" pairing would need a proper id-keyed queue instead.
class TranscriptRecorder
  def initialize(conversation)
    @conversation = conversation
    @seq = conversation.next_seq
    @pending_tool_call = nil
    @thinking_buffer = +""
    @content_buffer = +""
  end

  def start
    broadcast_status(running: true)
  end

  def finish
    flush_thinking
    flush_content
    broadcast_status(running: false)
  end

  def record_content(chunk)
    thinking_delta = chunk.respond_to?(:thinking) ? chunk.thinking&.text : nil
    if thinking_delta.present?
      flush_content
      @thinking_buffer << thinking_delta
    end

    content_delta = chunk.content.to_s
    return if content_delta.empty?

    flush_thinking
    @content_buffer << content_delta
  end

  def record_tool_call(tool_call)
    flush_thinking
    flush_content
    @pending_tool_call = tool_call
    persist(:tool_use, { tool_use_id: tool_call.id, tool_name: tool_call.name, tool_input: tool_call.arguments })
  end

  def record_tool_result(result)
    persist(:tool_result, { tool_use_id: @pending_tool_call&.id, content: result.to_s })
  end

  private

  def flush_thinking
    return if @thinking_buffer.empty?

    persist(:assistant_thinking, { text: @thinking_buffer }, broadcast: false)
    @thinking_buffer = +""
  end

  def flush_content
    return if @content_buffer.empty?

    persist(:assistant, { text: @content_buffer })
    @content_buffer = +""
  end

  def persist(msg_type, payload, broadcast: true)
    message = @conversation.messages.create!(uuid: SecureRandom.uuid, seq: @seq, msg_type:, payload:)
    @seq += 1
    broadcast_message(message) if broadcast
    message
  end

  def broadcast_message(message)
    return unless defined?(Turbo::StreamsChannel)

    Turbo::StreamsChannel.broadcast_append_to(
      "task_#{@conversation.task_id}",
      target: "transcript",
      partial: "messages/message",
      locals: { message: }
    )
  end

  def broadcast_status(running:)
    return unless defined?(Turbo::StreamsChannel)

    # The agent_status partial needs `task` to build the heartbeat URL, so the
    # live-broadcast render must pass it too -- not just the initial page render
    # via _task_header. Omitting it raises ActionView::Template::Error mid-run.
    Turbo::StreamsChannel.broadcast_replace_to(
      "task_#{@conversation.task_id}",
      target: "agent-status",
      partial: "tasks/agent_status",
      locals: { running:, task: @conversation.task }
    )
  end
end
