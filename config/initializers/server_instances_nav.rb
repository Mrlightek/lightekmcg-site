Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |feature|
    feature.slug = :server_instances
    feature.label = "Servers & Applications"
    feature.icon = "server"
    feature.gem_source = "lightekmcg-site"
    feature.nav_section = :operations
    feature.min_plan = :starter
    feature.nav_items = [{label: "Servers & Applications", icon: "server", path: "main_app.dashboard_servers_path"}]
  end
end
