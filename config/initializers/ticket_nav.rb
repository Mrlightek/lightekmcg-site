# frozen_string_literal: true
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_tickets; f.label = "Tickets"; f.icon = "ticket"
    f.gem_source = "host"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [
      { label: "Tickets", icon: "ticket", path: "main_app.employee_tickets_path" },
      { label: "New Ticket", icon: "plus", path: "main_app.new_employee_ticket_path" },
      { label: "Ticket Templates", icon: "copy", path: "main_app.support_ticket_templates_path" }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Tickets] nav registration skipped: #{e.message}"
end
