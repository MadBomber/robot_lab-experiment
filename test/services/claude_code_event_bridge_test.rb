require "test_helper"

class ClaudeCodeEventBridgeTest < ActiveSupport::TestCase
  def setup
    @repo_dir = init_git_repo("claude_code_event_bridge_test_repo")
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    task = Task.create!(project:, title: "Do the thing")
    @conversation = Conversation.create!(task:, provider: "claude_code", model: "sonnet", started_at: Time.current)
    @recorder = TranscriptRecorder.new(@conversation)
    @cancel = false
  end

  def teardown
    FileUtils.remove_entry(@repo_dir, true)
  end

  test "tool_use and tool_result blocks become transcript rows paired by id" do
    bridge.call(assistant_tool_uses(["toolu_1", "Read", { "file_path" => "a.rb" }],
                                    ["toolu_2", "mcp__task__read_task_doc", {}]))
    bridge.call(user_tool_results(["toolu_1", "line 1"], ["toolu_2", [{ "type" => "text", "text" => "the doc" }]]))

    rows = @conversation.messages.order(:seq).map { [it.msg_type, it.payload] }
    assert_equal %w[tool_use tool_use tool_result tool_result], rows.map(&:first)
    assert_equal "Read", rows[0].last["tool_name"]
    assert_equal({ "file_path" => "a.rb" }, rows[0].last["tool_input"])
    assert_equal ["toolu_1", "line 1"], rows[2].last.values_at("tool_use_id", "content")
    assert_equal ["toolu_2", "the doc"], rows[3].last.values_at("tool_use_id", "content")
  end

  test "events without tool blocks are ignored" do
    bridge.call({ "type" => "assistant", "message" => { "content" => [{ "type" => "text", "text" => "hi" }] } })
    bridge.call({ "type" => "stream_event", "event" => {} })
    bridge.call({ "type" => "result", "result" => "done" })
    bridge.call({ "type" => "user", "message" => { "content" => "plain prompt" } })

    assert_equal 0, @conversation.messages.count
  end

  test "a requested cancel raises Cancelled after recording the tool call" do
    @cancel = true

    assert_raises(AgentRunJob::Cancelled) { bridge.call(assistant_tool_uses(["toolu_1", "Bash", { "command" => "ls" }])) }
    assert_equal ["tool_use"], @conversation.messages.pluck(:msg_type)
  end

  test "a repeating tool call trips the plateau monitor" do
    looping = bridge(monitor: PlateauMonitor.new(identical_call_limit: 2))
    looping.call(assistant_tool_uses(["toolu_1", "Bash", { "command" => "gh run view" }]))

    assert_raises(PlateauMonitor::Plateaued) do
      looping.call(assistant_tool_uses(["toolu_2", "Bash", { "command" => "gh run view" }]))
    end
  end

  test "a repeating tool result trips the plateau monitor" do
    stuck = bridge(monitor: PlateauMonitor.new(identical_result_limit: 2))
    stuck.call(user_tool_results(["toolu_1", "still failing"]))

    assert_raises(PlateauMonitor::Plateaued) { stuck.call(user_tool_results(["toolu_2", "still failing"])) }
  end

  test "result_text flattens content blocks and stringifies anything else" do
    assert_equal "a\nb", ClaudeCodeEventBridge.result_text([{ "type" => "text", "text" => "a" }, "b"])
    assert_equal "plain", ClaudeCodeEventBridge.result_text("plain")
    assert_equal "", ClaudeCodeEventBridge.result_text(nil)
  end

  private

  def bridge(monitor: PlateauMonitor.new)
    ClaudeCodeEventBridge.new(recorder: @recorder, monitor:, cancel_requested: -> { @cancel })
  end

  def assistant_tool_uses(*calls)
    blocks = calls.map { |id, name, input| { "type" => "tool_use", "id" => id, "name" => name, "input" => input } }
    { "type" => "assistant", "message" => { "content" => blocks } }
  end

  def user_tool_results(*results)
    blocks = results.map { |id, content| { "type" => "tool_result", "tool_use_id" => id, "content" => content } }
    { "type" => "user", "message" => { "content" => blocks } }
  end
end
