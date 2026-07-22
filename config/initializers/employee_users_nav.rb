# frozen_string_literal: true
# Users nav item — admin-only (User#can_access_feature?(:employee_users)).
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_users; f.label = "Users"; f.icon = "users-group"
    f.gem_source = "host"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [{ label: "Users", icon: "users-group", path: "employee_users_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[Users] nav registration skipped: #{e.message}"
end
