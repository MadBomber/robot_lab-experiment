module MessagesHelper
  SUMMARY_LENGTH = 90

  ICONS = {
    "user" => <<~SVG,
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="8" r="3.4"/><path d="M4.5 20c0-4.1 3.4-7 7.5-7s7.5 2.9 7.5 7"/></svg>
    SVG
    "assistant" => <<~SVG,
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M12 2 L14 10 L22 12 L14 14 L12 22 L10 14 L2 12 L10 10 Z"/></svg>
    SVG
    "assistant_thinking" => <<~SVG,
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="6" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18" cy="12" r="1.4"/></svg>
    SVG
    "tool_use" => <<~SVG,
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a4 4 0 1 1-5.4 5.4L4 17l3 3 5.3-5.3a4 4 0 0 0 5.4-5.4l-2.6 2.6-2-2 2.6-2.6z"/></svg>
    SVG
    "tool_result" => <<~SVG,
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6l6 6-6 6"/><line x1="12" y1="18" x2="20" y2="18"/></svg>
    SVG
    "system" => <<~SVG,
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><rect x="4" y="4" width="3" height="3"/><rect x="17" y="4" width="3" height="3"/><rect x="4" y="17" width="3" height="3"/><rect x="17" y="17" width="3" height="3"/></svg>
    SVG
    "result" => <<~SVG
      <svg class="tp-msg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M8 12l3 3 5-6"/></svg>
    SVG
  }.freeze

  # Static, hand-authored SVGs (no interpolated data) -- safe to mark html_safe.
  def message_icon(msg_type)
    ICONS.fetch(msg_type, ICONS["system"]).html_safe
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
