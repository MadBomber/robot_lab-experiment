class Message < ApplicationRecord
  belongs_to :conversation

  enum :msg_type, {
    user: "user",
    assistant: "assistant",
    assistant_thinking: "assistant_thinking",
    tool_use: "tool_use",
    tool_result: "tool_result",
    system: "system",
    result: "result"
  }

  validates :uuid, presence: true, uniqueness: { scope: :conversation_id }
  validates :seq, presence: true
end
