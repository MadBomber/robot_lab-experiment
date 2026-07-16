require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("conversation_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    @task = Task.create!(project:, title: "Do the thing")
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "next_seq is 1 for a conversation with no messages yet" do
    conversation = Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    assert_equal 1, conversation.next_seq
  end

  test "next_seq follows the highest existing seq" do
    conversation = Conversation.create!(task: @task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
    conversation.messages.create!(uuid: "a", seq: 1, msg_type: "user", payload: { content: "hi" })
    conversation.messages.create!(uuid: "b", seq: 5, msg_type: "assistant", payload: { text: "hello" })

    assert_equal 6, conversation.next_seq
  end

  test "requires provider, model, and started_at" do
    conversation = Conversation.new(task: @task)
    assert_not conversation.valid?
    assert_includes conversation.errors[:provider], "can't be blank"
    assert_includes conversation.errors[:model], "can't be blank"
    assert_includes conversation.errors[:started_at], "can't be blank"
  end
end
