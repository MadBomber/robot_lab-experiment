require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  include MessagesHelper

  test "message_summary_line formats a tool_use as its arguments" do
    message = Message.new(msg_type: "tool_use", payload: { "tool_name" => "read_file", "tool_input" => { "path" => "app.rb" } })
    assert_equal({ "path" => "app.rb" }.to_s, message_summary_line(message))
  end

  test "message_summary_line returns the tool_result content" do
    message = Message.new(msg_type: "tool_result", payload: { "content" => "3 runs, 0 failures" })
    assert_equal "3 runs, 0 failures", message_summary_line(message)
  end

  test "message_summary_line returns the thinking text" do
    message = Message.new(msg_type: "assistant_thinking", payload: { "text" => "Let me check the Gemfile first." })
    assert_equal "Let me check the Gemfile first.", message_summary_line(message)
  end

  test "message_summary_line squishes newlines and truncates long content" do
    long_text = ("word " * 40).strip
    message = Message.new(msg_type: "tool_result", payload: { "content" => "line one\nline two\n#{long_text}" })

    summary = message_summary_line(message)

    assert_not_includes summary, "\n"
    assert_operator summary.length, :<=, MessagesHelper::SUMMARY_LENGTH
  end

  test "message_summary_line is nil for message types that don't collapse" do
    message = Message.new(msg_type: "assistant", payload: { "text" => "Done." })
    assert_nil message_summary_line(message)
  end
end
