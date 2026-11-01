# frozen_string_literal: true
# Candidate overlay only. Real installed Rails/private engines and PostgreSQL;
# all controlled ticket, KB, page, and Gatekeeper writes roll back together.
require "json"
require "rack/mock"
require "active_job/queue_adapters/test_adapter"
require "action_dispatch/testing/integration"
raise "Installed production runtime required" unless Rails.env.production?
candidate = File.expand_path("..", __dir__)
raise "Candidate must be separate from installed application" if File.realpath(candidate) == File.realpath(Rails.root)
ActiveJob::Base.queue_adapter = :test
%w[work_order ticket_approval structured_ticket structured_actions structured_execution].each do |name|
  "NevaehIntelligences::#{name.camelize}".constantize
  load File.join(candidate, "app/services/nevaeh_intelligences/#{name}.rb")
end
Dir[File.join(candidate, "app/services/nevaeh_intelligences/structured_workers/*.rb")].sort.each { |path| load path }
%w[knowledge_procedures teach_core_procedures].each { |name| load File.join(candidate, "app/services/nevaeh_intelligences/#{name}.rb") }
Marlon::Ticket
load File.join(candidate, "app/models/marlon/ticket.rb")
Employee::TicketsController
load File.join(candidate, "app/controllers/employee/tickets_controller.rb")
report = {}
ActiveRecord::Base.transaction do
  # Exercise the release's actual DDL in a rollback-only transaction.
  %w[20261101011000_create_nevaeh_ticket_templates 20261101012000_add_nevaeh_reporting_to_installations 20261101013000_add_nevaeh_knowledge_bundle_to_rollouts].each do |name|
    load File.join(candidate, "db/migrate/#{name}.rb")
    name.sub(/\A[0-9]+_/, "").camelize.constantize.new.migrate(:up)
  end
  GatekeeperInstallation.reset_column_information
  GatekeeperRollout.reset_column_information
  load File.join(candidate, "app/models/nevaeh_ticket_template.rb")
  operator = User.where(role: "super_admin").order(:id).first || raise("No installed super administrator")
  capability = NevaehCapability.find_by!(slug: NevaehIntelligences::StructuredTicket::CAPABILITY)
  raise "Operator has disabled the structured capability" unless capability.enabled?
  NevaehIntelligences::TeachCoreProcedures.call(root: candidate)
  available = NevaehIntelligences::KnowledgeProcedures.available
  raise "Core request lessons unavailable" unless available.keys.sort == NevaehIntelligences::StructuredTicket::ACTIONS.keys.sort
  site = LightekSettings::WebsiteIdentity.sites_for(operator).order(:id).first || raise("No operator-accessible website for controlled worker verification")
  ticket = Marlon::Ticket.create!(category: "technical", title: "Controlled KB worker acceptance", priority: "medium", urgency: 5, status: "open", submitted_by: operator)
  sections = [{"id" => "page", "action" => "site.page.create", "inputs" => {"site_id" => site.id, "title" => "KB worker acceptance", "slug" => "nevaeh-kb-#{SecureRandom.hex(8)}"}}]
  definition = LightekDesign::Catalog.section_definitions.first || raise("No installed design section")
  allowed = definition.fetch("fields").map { |field| field.fetch("name") }
  sections << {"id" => "content", "action" => "site.section.add", "inputs" => {"site_id" => site.id, "page_id" => "@page.page_id", "kind" => definition.fetch("kind"), "data" => {}}}
  order = NevaehIntelligences::StructuredTicket.attach!(ticket: ticket, actor: operator, sections: sections, automatic: true)
  fields = ticket.reload.extra_fields
  fields["nevaeh"] = {"actor_id" => operator.id, "reservation_id" => SecureRandom.uuid, "work_order_sha256" => NevaehIntelligences::TicketApproval.fingerprint(order)}
  ticket.update!(extra_fields: fields)
  result = NevaehIntelligences::StructuredExecution.execute!(ticket: ticket, reservation: fields.fetch("nevaeh").fetch("reservation_id"))
  raise "Worker lifecycle did not verify and close" unless result["verified"] && ticket.reload.status == "resolved" && ticket.extra_fields.dig("nevaeh", "knowledge_article_id")
  solution = DymondKb::Article.find(ticket.extra_fields.dig("nevaeh", "knowledge_article_id"))
  raise "Solution omitted KB revisions" unless solution.metadata.to_h["procedure_revisions"].size == 2
  pinned = order.fetch("inputs").fetch("sections").first.fetch("procedure")
  lesson = DymondKb::Article.find(pinned.fetch("article_id"))
  raise "Verified evidence was not learned" unless lesson.metadata.to_h.dig("nevaeh_verified_executions", ticket.id.to_s)
  # A movie ticket uses the actual historical JSON preset and creates real
  # persisted camera/scene/geometry records through its registered worker.
  movie_definition = available.fetch("studio.project.from_template")
  movie_inputs = movie_definition.fetch("defaults").merge("site_id" => site.id, "name" => "Controlled movie ticket")
  movie_output = NevaehIntelligences::StructuredActions.perform("studio.project.from_template", movie_inputs, actor: operator, ticket: ticket)
  NevaehIntelligences::StructuredActions.verify!("studio.project.from_template", movie_inputs, movie_output, actor: operator)
  report["movie_project_cameras_and_settings_verified"] = true
  template = NevaehTicketTemplate.create!(user: operator, name: "Controlled movie template", sections: [{"id" => "movie", "action" => "studio.project.from_template", "inputs" => movie_inputs}])
  raise "Ticket template revision missing" unless template.reusable_sections!.first.dig("procedure", "article_id")
  template.update!(name: "Updated controlled template")
  raise "Template update failed" unless template.reload.name == "Updated controlled template"
  template.destroy!
  report["ticket_template_crud_verified"] = true
  # Render through authenticated native HTTP and the real DymondDash layout.
  %w[support_ticket_templates_controller supports_controller employee/nevaeh_lessons_controller].each do |name|
    load File.join(candidate, "app/controllers/#{name}.rb")
  end
  load File.join(candidate, "config/routes.rb")
  [SupportTicketTemplatesController, SupportsController, Employee::TicketsController, Employee::NevaehLessonsController].each { |klass| klass.prepend_view_path(File.join(candidate, "app/views")) }
  email = "nevaeh-acceptance-#{SecureRandom.hex(8)}@example.invalid"
  password = SecureRandom.hex(24)
  account = User.create!(email_address: email, password: password, password_confirmation: password, first_name: "Controlled", last_name: "Acceptance", role: "super_admin")
  browser = ActionDispatch::Integration::Session.new(Rails.application)
  browser.https!
  browser.host!('lightekmcg.com')
  browser.post('/session', params: {email_address: email, password: password}, as: :json)
  raise "Controlled native login failed" unless browser.response.redirect? && Session.where(user_id: account.id).exists?
  paths = ['/employee/tickets/new', '/support_ticket_templates', '/support_ticket_templates/new', '/employee/nevaeh_lessons', '/supports?procedure=studio.project.from_template']
  paths.each do |path|
    browser.get(path)
    raise "Dashboard request failed #{path}: #{browser.response.status}" unless browser.response.status == 200
  end
  raise "Movie ticket fields missing from rendered form" unless browser.response.body.include?('Camera lens') && browser.response.body.include?('4096')
  report["authenticated_dashboard_and_request_forms"] = paths
  lesson.update!(body: lesson.body.to_s + "\nControlled amendment")
  begin
    NevaehIntelligences::KnowledgeProcedures.validate_steps!(order.fetch("inputs").fetch("sections"))
    raise "Stale KB revision was accepted"
  rescue NevaehIntelligences::KnowledgeProcedures::Invalid
    report["stale_revision_rejected"] = true
  end
  report.merge!("registered_workers" => available.values.map { |row| row.fetch("worker") }, "gatekeeper_authorized" => true,
    "page_and_section_created_and_reloaded" => true, "acceptance_verified" => true, "solution_recorded_in_kb" => true,
    "ticket_closed_after_acceptance" => true, "writes" => "rolled_back_controlled_cases", "mail_delivery" => "not_attempted")
  raise ActiveRecord::Rollback
end
puts "NEVAEH_KB_WORKER_ACCEPTANCE=#{JSON.generate(report)}"
