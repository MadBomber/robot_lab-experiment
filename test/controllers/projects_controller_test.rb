require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @repo_dir = Dir.mktmpdir("projects_controller_test_repo")
    Dir.chdir(@repo_dir) { system("git", "init", "--quiet") }
  end

  def teardown
    FileUtils.remove_entry(@repo_dir)
  end

  test "index lists projects" do
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    get projects_url
    assert_response :success
    assert_select "a", text: project.name
  end

  test "create with a valid repo path redirects to the new project" do
    assert_difference("Project.count", 1) do
      post projects_url, params: { project: { name: "Demo", repo_folder_path: @repo_dir } }
    end
    assert_redirected_to project_url(Project.last)
  end

  test "create with a non-repo path re-renders the form with an error" do
    non_repo = Dir.mktmpdir("not_a_repo")
    assert_no_difference("Project.count") do
      post projects_url, params: { project: { name: "Demo", repo_folder_path: non_repo } }
    end
    assert_response :unprocessable_entity
  ensure
    FileUtils.remove_entry(non_repo)
  end

  test "show lists the project's tasks" do
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    task = Task.create!(project:, title: "Do the thing")
    get project_url(project)
    assert_response :success
    assert_select "a", text: task.title
  end

  test "show lists open GitHub issues with a create-task link" do
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    issue = GithubIssueService::Issue.new(number: 5, title: "Fix the thing", body: nil,
                                          url: "https://github.com/x/y/issues/5")

    GithubIssueService.stub(:list, ->(*_args) { [issue] }) do
      get project_url(project)
    end

    assert_response :success
    assert_select "a[href=?]", new_project_task_path(project, from_issue: 5), text: "Create task"
  end

  test "edit shows the form" do
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    get edit_project_url(project)
    assert_response :success
    assert_select "h1", text: "Edit project"
    assert_select "input[name='project[name]'][value='Demo']"
  end

  test "update edits name and subproject_path" do
    project = Project.create!(name: "Old Name", repo_folder_path: @repo_dir, subproject_path: nil)
    patch project_url(project), params: { project: { name: "New Name", subproject_path: "libs/core" } }
    assert_redirected_to project_url(Project.find_by(name: "New Name"))
    assert_equal "New Name", project.reload.name
    assert_equal "libs/core", project.subproject_path
  end

  test "update allows repo_folder_path change when no tasks exist" do
    new_repo_dir = Dir.mktmpdir("update_move_repo")
    Dir.chdir(new_repo_dir) { system("git", "init", "--quiet") }
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    patch project_url(project), params: { project: { repo_folder_path: new_repo_dir } }
    assert_redirected_to project_url(Project.find_by(repo_folder_path: new_repo_dir))
    assert_equal new_repo_dir, project.reload.repo_folder_path
  ensure
    FileUtils.remove_entry(new_repo_dir) if defined?(new_repo_dir)
  end

  test "update blocks repo_folder_path change when tasks exist" do
    project = Project.create!(name: "Demo", repo_folder_path: @repo_dir)
    Task.create!(project:, title: "Do the thing")
    patch project_url(project), params: { project: { name: "Renamed", repo_folder_path: "/some/new/path" } }
    assert_response :redirect
    task = Project.find_by(name: "Renamed")
    # name was saved successfully, repo_folder_path was blocked
    assert_equal @repo_dir, task.repo_folder_path  # repo_folder_path unchanged (blocked)
    assert_equal "Renamed", task.name  # name was saved successfully
  end

  test "destroy deletes the project" do
    project = Project.create!(name: "To Delete", repo_folder_path: @repo_dir)
    delete project_url(project)
    assert_redirected_to projects_url
    refute Project.exists?(project.id)
  end
end
