require "securerandom"

# Persists a conversation's streaming output as idempotent, ordered Message
# rows, and broadcasts each one over Turbo Streams for a live transcript view.
# One instance per AgentRunJob#perform call -- not safe to share across runs.
#
# Tool call/result pairing assumes sequential tool execution (the default);
# if robot_lab ever enables ruby_llm's concurrent tool execution, this naive
# "last tool_call wins" pairing would need a proper id-keyed queue instead.
class TranscriptRecorder
  def initialize(conversation)
    @conversation = conversation
    @seq = conversation.next_seq
    @pending_tool_call = nil
  end

  def record_content(chunk)
    thinking = chunk.respond_to?(:thinking) ? chunk.thinking : nil
    persist(:assistant_thinking, { text: thinking.text }) if thinking&.text.present?

    text = chunk.content.to_s
    persist(:assistant, { text: }) unless text.empty?
  end

  def record_tool_call(tool_call)
    @pending_tool_call = tool_call
    persist(:tool_use, { tool_use_id: tool_call.id, tool_name: tool_call.name, tool_input: tool_call.arguments })
  end

  def record_tool_result(result)
    persist(:tool_result, { tool_use_id: @pending_tool_call&.id, content: result.to_s })
  end

  private

  def persist(msg_type, payload)
    message = @conversation.messages.create!(uuid: SecureRandom.uuid, seq: @seq, msg_type:, payload:)
    @seq += 1
    broadcast(message)
    message
  end

  def broadcast(message)
    return unless defined?(Turbo::StreamsChannel)

    Turbo::StreamsChannel.broadcast_append_to(
      "task_#{@conversation.task_id}",
      target: "transcript",
      partial: "messages/message",
      locals: { message: }
    )
  end
end
