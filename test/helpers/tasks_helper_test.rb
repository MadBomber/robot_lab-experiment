require "test_helper"

class TasksHelperTest < ActionView::TestCase
  include TasksHelper

  test "maps each task status to its badge variant" do
    assert_equal :outline, task_status_badge_variant("pending")
    assert_equal :info,    task_status_badge_variant("in_progress")
    assert_equal :warning, task_status_badge_variant("in_review")
    assert_equal :success, task_status_badge_variant("completed")
  end

  test "accepts symbols and falls back to outline for unknown statuses" do
    assert_equal :info,    task_status_badge_variant(:in_progress)
    assert_equal :outline, task_status_badge_variant("garbage")
    assert_equal :outline, task_status_badge_variant(nil)
  end
end
