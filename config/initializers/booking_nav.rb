# frozen_string_literal: true
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :booking; f.label = "Booking"; f.icon = "calendar"
    f.gem_source = "booking"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [{ label: "Booking Calendar", icon: "calendar", path: "dymond_dash.booking_dashboard_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[Booking] nav registration skipped: #{e.message}"
end
