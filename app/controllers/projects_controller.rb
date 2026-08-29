class ProjectsController < ApplicationController
  def index
    @projects = Project.order(:name)
    @llm_options = Project.llm_options
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
    rescue ProjectDestructionService::CleanupError => e
      # DB destroy succeeded; only best-effort filesystem cleanup partially
      # failed -- a much smaller problem, so this stays a notice rather than
      # an alert, mirroring TasksController#clear_completed's severity for
      # the same "mostly succeeded, stray leftover" outcome.
      redirect_to projects_url, notice: e.message
    rescue ProjectDestructionService::Error => e
      redirect_to projects_url, alert: e.message
    end
  end

  # Sets which LLM provider/model new agent runs for this project use --
  # a narrower sibling of #update so the index page's inline picker can save
  # without leaving the index (see AgentRunner#effective_provider/#effective_model
  # for the fallback to AgentRunner::DEFAULT_PROVIDER/DEFAULT_MODEL).
  def update_llm
    @project = Project.find(params[:id])

    if @project.update(llm_params)
      redirect_to projects_path, notice: "LLM settings updated for #{@project.name}."
    else
      redirect_to projects_path, alert: @project.errors.full_messages.to_sentence
    end
  end

  private

  def project_params
    params.expect(project: %i[name repo_folder_path subproject_path])
  end

  def llm_params
    permitted = params.expect(project: %i[llm_provider llm_model])
    { llm_provider: permitted[:llm_provider].presence, llm_model: permitted[:llm_model].presence }
  end
end
