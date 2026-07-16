class WriteTaskDocTool < TaskScopedTool
  description "Overwrite the task doc with new content. Read it first so you don't lose sections you didn't intend to change."
  param :content, type: "string", desc: "The full new content of the task doc."

  def execute(content:)
    TaskDocument.write(task, content)
    "Task doc updated (#{content.bytesize} bytes)."
  end
end
