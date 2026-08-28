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
  validates :msg_type, presence: true
  # presence: true would reject `{}` (an empty Hash is blank) -- payload is a
  # JSON column that's legitimately `{}` in tests and for some msg_types, so
  # only nil is actually invalid.
  validates :payload, exclusion: { in: [nil], message: "can't be blank" }
end
