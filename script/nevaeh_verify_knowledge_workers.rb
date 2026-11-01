# frozen_string_literal: true
# Candidate overlay only. Real installed Rails/private engines and PostgreSQL;
# all controlled ticket, KB, page, and Gatekeeper writes roll back together.
require "json"
require "rack/mock"
require "active_job/queue_adapters/test_adapter"
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
  sections << {"id" => "content", "action" => "site.section.add", "inputs" => {"site_id" => site.id, "page_id" => "@page.page_id", "kind" => definition.fetch("kind"), "data" => definition.fetch("data", {}).slice(*allowed)}}
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
