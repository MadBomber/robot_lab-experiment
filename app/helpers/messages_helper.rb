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
    ICON_NAMES[msg_type] || :settings
  end

  def message_badge_variant(msg_type)
    BADGE_VARIANTS[msg_type] || :outline
  end

  # One-line preview shown in a collapsed transcript entry's <summary>, before
  # the full payload is revealed. nil for message types that don't collapse.
  def message_summary_line(message)
    source = message.summary_source
    truncate_summary(source) unless source.nil?
  end

  private

  def truncate_summary(text)
    text.to_s.squish.truncate(SUMMARY_LENGTH)
  end
end
