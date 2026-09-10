module ApplicationHelper
  # Rails flash key -> poetry toast variant, for the layout's flash -> toast
  # recipe. :destructive announces assertively, so it is reserved for alerts;
  # unknown keys fall back to the neutral default treatment.
  FLASH_TOAST_VARIANTS = {
    "alert"  => :destructive,
    "notice" => :success
  }.freeze

  def flash_toast_variant(kind)
    FLASH_TOAST_VARIANTS[kind.to_s] || :default
  end
end
