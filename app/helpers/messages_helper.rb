module MessagesHelper
  SUMMARY_LENGTH = 90

  # Lucide icon per transcript message type, rendered via poetry_icon.
  ICON_NAMES = {
    "user"               => :user,
    "assistant"          => :bot,
    "assistant_thinking" => :brain,
    "tool_use"           => :wrench,
    "tool_result"        => :terminal,
    "system"             => :settings,
    "result"             => :'circle-check'
  }.freeze

  # Poetry badge variant per message type. One treatment family per surface:
  # the soft trio (success/warning/info) plus outline for neutral rows.
  BADGE_VARIANTS = {
    "user"               => :outline,
    "assistant"          => :info,
    "assistant_thinking" => :outline,
    "tool_use"           => :warning,
    "tool_result"        => :success,
    "system"             => :outline,
    "result"             => :success
  }.freeze

  def message_icon_name(msg_type)
    ICON_NAMES.fetch(msg_type, :settings)
  end

  def message_badge_variant(msg_type)
    BADGE_VARIANTS.fetch(msg_type, :outline)
  end

  # One-line preview shown in a collapsed transcript entry's <summary>, before
  # the full payload is revealed. nil for message types that don't collapse.
  def message_summary_line(message)
    case message.msg_type
    when "tool_use"
      truncate_summary(message.payload["tool_input"].to_s)
    when "tool_result"
      truncate_summary(message.payload["content"])
    when "assistant_thinking"
      truncate_summary(message.payload["text"])
    end
  end

  private

  def truncate_summary(text)
    text.to_s.squish.truncate(SUMMARY_LENGTH)
  end
end
