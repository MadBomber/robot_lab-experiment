require "test_helper"

class TranscriptRecorderTest < ActiveSupport::TestCase
  FakeChunk = Struct.new(:content, :thinking)
  FakeThinking = Struct.new(:text)

  def setup
    @repo_dir = Dir.mktmpdir("transcript_recorder_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    task = Task.create!(project:, title: "Do the thing")
    @conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    @recorder = TranscriptRecorder.new(@conversation)
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "record_content buffers deltas and flushes one assistant message on finish" do
    @recorder.record_content(FakeChunk.new("hel", nil))
    @recorder.record_content(FakeChunk.new("lo", nil))
    assert_equal 0, @conversation.messages.count

    @recorder.finish

    message = @conversation.messages.sole
    assert message.assistant?
    assert_equal "hello", message.payload["text"]
  end

  test "record_content skips empty text chunks" do
    @recorder.record_content(FakeChunk.new("", nil))
    @recorder.finish
    assert_equal 0, @conversation.messages.count
  end

  test "thinking deltas are buffered and flushed as one message when content starts" do
    @recorder.record_content(FakeChunk.new(nil, FakeThinking.new("rea")))
    @recorder.record_content(FakeChunk.new(nil, FakeThinking.new("soning")))
    @recorder.record_content(FakeChunk.new("answer", nil))
    @recorder.finish

    messages = @conversation.messages.order(:seq)
    assert_equal %w[assistant_thinking assistant], messages.pluck(:msg_type)
    assert_equal "reasoning", messages.first.payload["text"]
    assert_equal "answer", messages.second.payload["text"]
  end

  test "finish flushes trailing buffered thinking with nothing else forcing it" do
    @recorder.record_content(FakeChunk.new(nil, FakeThinking.new("thinking")))
    @recorder.finish

    message = @conversation.messages.sole
    assert message.assistant_thinking?
    assert_equal "thinking", message.payload["text"]
  end

  test "thinking messages are persisted but never broadcast live" do
    calls = []
    Turbo::StreamsChannel.stub(:broadcast_append_to, ->(*_args, **kwargs) { calls << kwargs }) do
      @recorder.record_content(FakeChunk.new(nil, FakeThinking.new("secret reasoning")))
      @recorder.finish
    end

    assert_equal 1, @conversation.messages.count
    assert(calls.none? { |kwargs| kwargs.dig(:locals, :message)&.assistant_thinking? })
  end

  test "start broadcasts the spinner on, finish broadcasts it off" do
    calls = []
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*_args, **kwargs) { calls << kwargs }) do
      @recorder.start
      @recorder.finish
    end

    assert_equal([true, false], calls.map { |kwargs| kwargs.dig(:locals, :running) })
  end

  test "status broadcast passes the task so the agent_status partial can build its heartbeat URL" do
    calls = []
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*_args, **kwargs) { calls << kwargs }) do
      @recorder.start
      @recorder.finish
    end

    assert(calls.all? { |kwargs| kwargs.dig(:locals, :task) == @conversation.task },
           "every agent_status broadcast must include task: (omitting it raises in the partial mid-run)")
  end

  test "seq numbers stay monotonic across flush boundaries and a fresh recorder" do
    @recorder.record_content(FakeChunk.new(nil, FakeThinking.new("thinking")))
    @recorder.record_tool_call(RubyLLM::ToolCall.new(id: "t1", name: "read_file", arguments: {}))
    @recorder.record_tool_result("result")
    @recorder.record_content(FakeChunk.new("answer", nil))
    @recorder.finish

    fresh_recorder = TranscriptRecorder.new(@conversation.reload)
    fresh_recorder.record_content(FakeChunk.new("more", nil))
    fresh_recorder.finish

    assert_equal [1, 2, 3, 4, 5], @conversation.messages.order(:seq).pluck(:seq)
  end

  test "record_tool_call flushes pending thinking before recording the tool call, and pairs via tool_use_id" do
    @recorder.record_content(FakeChunk.new(nil, FakeThinking.new("deciding what to do")))
    tool_call = RubyLLM::ToolCall.new(id: "abc", name: "read_file", arguments: { path: "x.txt" })
    @recorder.record_tool_call(tool_call)
    @recorder.record_tool_result("file body")

    types = @conversation.messages.order(:seq).pluck(:msg_type)
    assert_equal %w[assistant_thinking tool_use tool_result], types

    tool_use = @conversation.messages.find_by(msg_type: "tool_use")
    tool_result = @conversation.messages.find_by(msg_type: "tool_result")

    assert_equal "abc", tool_use.payload["tool_use_id"]
    assert_equal "abc", tool_result.payload["tool_use_id"]
    assert_equal "file body", tool_result.payload["content"]
  end
end
