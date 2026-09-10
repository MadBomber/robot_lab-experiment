require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "maps flash keys to toast variants" do
    assert_equal :destructive, flash_toast_variant("alert")
    assert_equal :success,     flash_toast_variant("notice")
  end

  test "accepts symbols and defaults unknown keys" do
    assert_equal :destructive, flash_toast_variant(:alert)
    assert_equal :default,     flash_toast_variant("warning")
  end
end
