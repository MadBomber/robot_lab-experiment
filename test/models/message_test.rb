require "test_helper"

class MessageTest < ActiveSupport::TestCase
  def setup
    @repo_dir = Dir.mktmpdir("message_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    task = Task.create!(project:, title: "Do the thing")
    @conversation = Conversation.create!(task:, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current)
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "uuid must be unique within a conversation" do
    @conversation.messages.create!(uuid: "dup", seq: 1, msg_type: "user", payload: {})
    dup = @conversation.messages.build(uuid: "dup", seq: 2, msg_type: "assistant", payload: {})

    assert_not dup.valid?
    assert_includes dup.errors[:uuid], "has already been taken"
  end

  test "the same uuid is allowed across different conversations" do
    @conversation.messages.create!(uuid: "shared", seq: 1, msg_type: "user", payload: {})

    other_task = Task.create!(project: @conversation.task.project, title: "Another task")
    other_conversation = Conversation.create!(
      task: other_task, provider: "ollama", model: "qwen3.6:latest", started_at: Time.current
    )
    other_message = other_conversation.messages.build(uuid: "shared", seq: 1, msg_type: "user", payload: {})

    assert other_message.valid?
  end

  test "supports the system msg_type without colliding with Kernel#system" do
    message = @conversation.messages.create!(uuid: "sys-1", seq: 1, msg_type: "system", payload: { text: "note" })

    assert message.system?
    assert_equal [message], Conversation.find(@conversation.id).messages.system
  end
end
