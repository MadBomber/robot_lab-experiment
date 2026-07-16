class ReadTaskDocTool < TaskScopedTool
  description "Read the current content of the task doc -- the shared plan/progress markdown file."

  def execute
    TaskDocument.read(task)
  end
end
