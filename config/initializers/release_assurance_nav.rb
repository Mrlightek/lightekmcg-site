# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)

  DymondDash::FeatureRegistry.register do |feature|
    feature.slug = :release_assurance
    feature.label = "Release Assurance"
    feature.icon = "checklist"
    feature.gem_source = "lightekmcg-site"
    feature.nav_section = :operations
    feature.min_plan = :starter
    feature.nav_items = [{ label: "Release Assurance", icon: "checklist", path: "main_app.dashboard_release_assurance_index_path" }]
  end
end
