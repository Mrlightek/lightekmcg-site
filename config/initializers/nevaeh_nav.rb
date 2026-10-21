# frozen_string_literal: true
# Nevaeh is a native DymondDash section; no separate sidebar or executable grants.
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)

  DymondDash::FeatureRegistry.register do |feature|
    feature.slug = :nevaeh
    feature.label = "Nevaeh"
    feature.icon = "brain"
    feature.gem_source = "host"
    feature.nav_section = :operations
    feature.min_plan = :starter
    feature.nav_items = [
      { label: "Nevaeh Overview", icon: "brain", path: "main_app.employee_nevaeh_overview_path" },
      { label: "Configuration", icon: "settings", path: "main_app.employee_nevaeh_configuration_path" },
      { label: "Draft Generator", icon: "code", path: "main_app.employee_nevaeh_generator_path" },
      { label: "Ticket Drafts", icon: "ticket", path: "main_app.employee_nevaeh_ticket_drafts_path" },
      { label: "Reviewed Candidates", icon: "code", path: "main_app.employee_nevaeh_reviewed_candidates_path" },
      { label: "Acceptance Evidence", icon: "shield", path: "main_app.employee_nevaeh_acceptance_evidence_path" },
      { label: "Criterion Coverage", icon: "check-square", path: "main_app.employee_nevaeh_coverage_path" },
      { label: "Review Packets", icon: "file-check", path: "main_app.employee_nevaeh_review_packets_path" },
      { label: "Capabilities", icon: "box", path: "main_app.employee_nevaeh_capabilities_path" },
      { label: "Trusted Services", icon: "server", path: "main_app.employee_nevaeh_services_path" },
      { label: "Tickets & Work Orders", icon: "ticket", path: "main_app.employee_tickets_path" }
    ]
  end
rescue StandardError => error
  Rails.logger.warn "[Nevaeh] dashboard navigation registration skipped: #{error.class}: #{error.message}"
end
