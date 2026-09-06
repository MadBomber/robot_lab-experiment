module TasksHelper
  # Poetry badge variant per task status -- the soft trio plus outline, one
  # treatment family per surface.
  STATUS_BADGE_VARIANTS = {
    "pending"     => :outline,
    "in_progress" => :info,
    "in_review"   => :warning,
    "completed"   => :success
  }.freeze

  def task_status_badge_variant(status)
    STATUS_BADGE_VARIANTS.fetch(status.to_s, :outline)
  end
end
