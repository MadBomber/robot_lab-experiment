class ProjectsController < ApplicationController
  def index
    @projects = Project.order(:name)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      redirect_to @project, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @project = Project.find(params[:id])
    @tasks = @project.tasks.order(created_at: :desc)
    @open_issues = GithubIssueService.list(@project)
  end

  private

  def project_params
    params.expect(project: %i[name repo_folder_path subproject_path])
  end
end
