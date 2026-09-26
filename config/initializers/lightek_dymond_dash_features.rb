# frozen_string_literal: true

# Host-application features exposed through DymondDash's native FeatureRegistry.
#
# DymondDash builds sidebar navigation from FeatureRegistry.nav_items_for, so
# Gatekeeper and Susu belong here rather than in a second navigation registry.
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :gatekeeper_infrastructure
    f.label       = "Infrastructure"
    f.icon        = "server"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan    = :starter
    f.nav_items   = [
      {
        label: "Infrastructure",
        icon: "server",
        path: "main_app.dashboard_infrastructure_path"
      }
    ]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :susu
    f.label       = "Susu"
    f.icon        = "users-group"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :services
    f.min_plan    = :starter
    f.nav_items   = [
      {
        label: "Susu",
        icon: "users-group",
        path: "main_app.dashboard_susu_path"
      }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Lightek/DymondDash] Host feature registration skipped: #{e.class}: #{e.message}"
end
