class Project < ApplicationRecord
  has_many :tasks, dependent: :destroy

  validates :name, presence: true
  validates :repo_folder_path, presence: true, uniqueness: true
  validate :repo_folder_path_must_be_a_git_repo

  def effective_cwd
    subproject_path.present? ? File.join(repo_folder_path, subproject_path) : repo_folder_path
  end

  private

  def repo_folder_path_must_be_a_git_repo
    return if repo_folder_path.blank?
    return if Dir.exist?(File.join(repo_folder_path, ".git"))

    errors.add(:repo_folder_path, "is not a git repository")
  end
end
