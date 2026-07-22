# frozen_string_literal: true
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :kb; f.label = "Knowledge Base"; f.icon = "book"
    f.gem_source = "kb"; f.nav_section = :platform; f.min_plan = :starter
    f.nav_items = [{ label: "Knowledge Base", icon: "book", path: "dymond_dash.kb_dashboard_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[KB] nav registration skipped: #{e.message}"
end
