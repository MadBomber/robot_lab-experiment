class ProjectDestructionService
  class Error < StandardError; end

  def initialize(project)
    @project = project
  end

  def call
    ActiveRecord::Base.transaction do
      @project.tasks.each do |task|
        WorktreeService.new(task).remove
        TaskDocument.delete_archive(task)
      end
      @project.destroy!
    end
  rescue => e
    raise Error, "Could not destroy project '#{@project.name}': #{e.message}"
  end
end
