Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |feature|
    feature.slug = :fleet_updates
    feature.label = "Customer Updates"
    feature.icon = "server"
    feature.gem_source = "lightekmcg-site"
    feature.nav_section = :operations
    feature.min_plan = :starter
    feature.nav_items = [{label: "Customer Updates", icon: "server", path: "main_app.dashboard_fleet_updates_path"}]
  end
end
