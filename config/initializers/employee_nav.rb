# frozen_string_literal: true
# Registers Clients in the dashboard nav — visible to employee/admin only,
# via User#can_access_feature?(:employee_clients).
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_clients; f.label = "Clients"; f.icon = "users"
    f.gem_source = "host"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [
      { label: "Clients", icon: "users", path: "employee_clients_path" }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Employee] nav registration skipped: #{e.message}"
end
