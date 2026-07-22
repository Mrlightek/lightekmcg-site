# frozen_string_literal: true
# Projects/Timesheets existed with working controllers but no nav entry —
# real gap, fixed here.
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_projects; f.label = "Projects"; f.icon = "briefcase"
    f.gem_source = "host"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [
      { label: "Projects",   icon: "briefcase", path: "employee_projects_path" },
      { label: "Timesheets", icon: "clock",     path: "employee_timesheets_path" }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Projects] nav registration skipped: #{e.message}"
end
