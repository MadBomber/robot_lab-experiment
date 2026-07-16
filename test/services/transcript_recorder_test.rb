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

  test "record_content persists an assistant message with the chunk text" do
    @recorder.record_content(FakeChunk.new("hello", nil))

    message = @conversation.messages.sole
    assert message.assistant?
    assert_equal "hello", message.payload["text"]
  end

  test "record_content skips empty text chunks" do
    @recorder.record_content(FakeChunk.new("", nil))
    assert_equal 0, @conversation.messages.count
  end

  test "record_content emits a separate assistant_thinking message when thinking text is present" do
    @recorder.record_content(FakeChunk.new("answer", FakeThinking.new("reasoning here")))

    types = @conversation.messages.order(:seq).pluck(:msg_type)
    assert_equal %w[assistant_thinking assistant], types
  end

  test "seq numbers are monotonic and continue across a fresh recorder for the same conversation" do
    @recorder.record_content(FakeChunk.new("first", nil))
    @recorder.record_content(FakeChunk.new("second", nil))

    fresh_recorder = TranscriptRecorder.new(@conversation.reload)
    fresh_recorder.record_content(FakeChunk.new("third", nil))

    assert_equal [1, 2, 3], @conversation.messages.order(:seq).pluck(:seq)
  end

  test "record_tool_call then record_tool_result pairs them via tool_use_id" do
    tool_call = RubyLLM::ToolCall.new(id: "abc", name: "read_file", arguments: { path: "x.txt" })
    @recorder.record_tool_call(tool_call)
    @recorder.record_tool_result("file body")

    tool_use = @conversation.messages.find_by(msg_type: "tool_use")
    tool_result = @conversation.messages.find_by(msg_type: "tool_result")

    assert_equal "abc", tool_use.payload["tool_use_id"]
    assert_equal "abc", tool_result.payload["tool_use_id"]
    assert_equal "file body", tool_result.payload["content"]
  end
end
