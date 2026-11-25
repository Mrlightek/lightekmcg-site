Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)

  DymondDash::FeatureRegistry.register do |feature|
    feature.slug = :feature_flags
    feature.label = "Feature Flags"
    feature.icon = "toggle-right"
    feature.gem_source = "lightekmcg-site"
    feature.nav_section = :operations
    feature.min_plan = :starter
    feature.nav_items = [{label: "Feature Flags", icon: "toggle-right", path: "main_app.dashboard_feature_flags_path"}]
  end
end
