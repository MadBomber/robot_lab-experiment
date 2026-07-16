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

  def edit
    @project = Project.find(params[:id])
  end

  def update
    @project = Project.find(params[:id])
    old_path = @project.repo_folder_path
    attempted_replacement = @project.tasks.any? && params[:project][:repo_folder_path].to_s != old_path

    if attempted_replacement
      params[:project].delete(:repo_folder_path)
    end

    if @project.update(project_params)
      flash[:alert] = "Repo folder path cannot be changed while the project has tasks." if attempted_replacement
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project = Project.find(params[:id])
    begin
      ProjectDestructionService.new(@project).call
      redirect_to projects_url, notice: "Project '#{@project.name}' and all associated tasks/worktrees have been deleted."
    rescue ProjectDestructionService::Error => e
      redirect_to projects_url, alert: e.message
    end
  end

  private

  def project_params
    params.expect(project: %i[name repo_folder_path subproject_path])
  end
end
