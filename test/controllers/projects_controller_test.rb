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
end
