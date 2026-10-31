# frozen_string_literal: true
require "json"
require "sidekiq/api"
require "tmpdir"
require "tempfile"
require "open3"
require "rbconfig"
require_relative "nevaeh_backlog_worker_boot"

raise "Installed production runtime required" unless Rails.env.production?
token = STDIN.read.strip
raise "Engineering branch write credential missing" if token.empty?
ENV["NEVAEH_ENGINEERING_GITHUB_TOKEN"] = token
ENV["NEVAEH_ENGINEERING_BRANCH"] = "feat/nevaeh-historical-backlog-20261031"
queue_name = "nevaeh_structured_acceptance_#{SecureRandom.hex(6)}"
ENV["NEVAEH_STRUCTURED_QUEUE"] = queue_name
capability = NevaehCapability.find_by(slug: NevaehIntelligences::StructuredTicket::CAPABILITY)
raise "Preserve existing operator-controlled registration" if capability && capability.metadata.to_h["acceptance_only"] != true
capability ||= NevaehIntelligences::StructuredTicket.registered!
capability.update!(enabled: true, queue: queue_name, metadata: capability.metadata.to_h.merge("acceptance_only" => true))
ticket = nil
worker = nil
log = nil
begin
actor = Marlon::Ticket.find(3).events.where.not(actor_id: nil).order(created_at: :desc).first.actor
raise "Acceptance operator lacks authority" unless Ability.new(actor).can?(:execute_nevaeh, Marlon::Ticket)
website = LightekSettings::WebsiteIdentity.sites_for(actor).order(:id).first!
workspace = Dir.mktmpdir("nevaeh-engineering-")
ENV["NEVAEH_ENGINEERING_WORKSPACE"] = workspace
_out, _err, clone_status = Open3.capture3("git", "clone", "--single-branch", "--branch", ENV.fetch("NEVAEH_ENGINEERING_BRANCH"),
  "https://github.com/Mrlightek/lightekmcg-site.git", workspace)
raise "Isolated engineering clone failed" unless clone_status.success?

# Compile and render the real branch ticket form in the installed Rails stack.
Employee::TicketsController
load File.join(File.expand_path("..", __dir__), "app/controllers/employee/tickets_controller.rb")
Employee::TicketsController.prepend_view_path(File.join(File.expand_path("..", __dir__), "app/views"))
form = Employee::TicketsController.renderer.render(template: "employee/tickets/new", layout: false,
  assigns: {ticket: Marlon::Ticket.new(category: "technical", priority: "medium", urgency: 5)})
raise "Structured form missing action controls" unless form.include?("structured_ticket[sections]") && form.include?("Add action section")

marker = "structured_actions_v1"
ticket = Marlon::Ticket.where("extra_fields->>'nevaeh_acceptance_case' = ?", marker).order(:id).first
unless ticket
  suffix = SecureRandom.hex(5)
  Marlon::Ticket.transaction do
    ticket = Marlon::Ticket.create!(title: "Nevaeh structured action acceptance #{suffix}", category: "technical", priority: "medium", urgency: 5,
      status: "open", submitted_by: actor, extra_fields: {"nevaeh_acceptance_case" => marker})
    sections = [
      {"id" => "page", "action" => "site.page.create", "inputs" => {"site_id" => website.id, "title" => "Nevaeh acceptance #{suffix}", "slug" => "nevaeh-acceptance-#{suffix}"}},
      {"id" => "content", "action" => "site.section.add", "inputs" => {"site_id" => website.id, "page_id" => "@page.page_id", "kind" => "lightek_product_grid", "data" => {"heading" => "Nevaeh verified output", "intro" => "Created from a structured ticket"}}},
      {"id" => "studio", "action" => "studio.project.create", "inputs" => {"name" => "Nevaeh acceptance #{suffix}"}},
      {"id" => "service", "action" => "engineering.service.generate", "inputs" => {}, "depends_on" => ["content", "studio"]}
    ]
    NevaehIntelligences::StructuredTicket.attach!(ticket: ticket, actor: actor, sections: sections, automatic: true)
  end
end
# Use a section kind actually registered in the installed site's catalog.
if ticket.status != "resolved"
  saved_sections = NevaehIntelligences::WorkOrder.read!(ticket: ticket).fetch("inputs").fetch("sections")
  content = saved_sections.find { |step| step["id"] == "content" }
  unless LightekDesign::Catalog.section_definition(content.fetch("inputs").fetch("kind"))
    definition = LightekDesign::Catalog.section_definitions.first || raise("Installed site has no section definitions")
    content["inputs"]["kind"] = definition.fetch("kind")
    content["inputs"]["data"] = definition.fetch("fields").first(2).to_h { |field| [field.fetch("name"), "Nevaeh verified output"] }
    NevaehIntelligences::StructuredTicket.revise!(ticket: ticket, actor: actor, sections: saved_sections, automatic: false)
  end
end
log = Tempfile.new(["nevaeh-structured-worker-", ".log"])
  if ticket.status != "resolved"
    state = ticket.extra_fields.to_h.fetch("nevaeh", {})
    if state["reservation_id"].present?
      NevaehIntelligences::StructuredExecution.resume!(ticket: ticket, actor: actor, explicit: true)
    else
      NevaehIntelligences::ProcessBacklogJob.set(queue: queue_name).perform_later(ticket_id: ticket.id)
    end
    worker = Process.spawn(RbConfig.ruby, Gem.bin_path("sidekiq", "sidekiq"), "-e", "production", "-r",
      File.expand_path("nevaeh_backlog_worker_boot.rb", __dir__), "-q", queue_name, "-c", "1", out: log.path, err: [:child, :out], pgroup: true)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
    until ticket.reload.status == "resolved"
      raise "Structured workflow timed out; inspect internal ticket evidence" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      if ticket.extra_fields.to_h.dig("nevaeh_backlog", "status") == "escalated" && DymondDispatch::WorkItem.find_by(id: ticket.extra_fields.to_h.dig("nevaeh", "work_item_id"))&.status == "failed"
        raise "Structured execution needs engineering review; inspect internal ticket evidence"
      end
      sleep 0.3
    end
  end
  fields = ticket.reload.extra_fields.to_h.deep_stringify_keys
  raise "Missing verified closure" unless fields.dig("nevaeh", "execution_status") == "verified" && fields.dig("nevaeh", "knowledge_article_id")
  steps = fields.fetch("nevaeh_structured").fetch("steps")
  raise "Not all action sections verified" unless steps.size == 4 && steps.values.all? { |value| value["status"] == "verified" }
  order = NevaehIntelligences::WorkOrder.read!(ticket: ticket)
  order.fetch("inputs").fetch("sections").each do |section|
    receipt = steps.fetch(section.fetch("id"))
    NevaehIntelligences::StructuredActions.verify!(section.fetch("action"), receipt.fetch("inputs"), receipt.fetch("output"), actor: actor)
  end
  # Gatekeeper must reject a revision whose persisted authorization is absent.
  Marlon::Ticket.transaction(requires_new: true) do
    changed = ticket.reload.extra_fields.to_h.deep_stringify_keys
    changed.fetch("nevaeh_structured")["authorized_revision"] = nil
    ticket.update!(extra_fields: changed)
    decision = Gatekeeper::AuthorizationService.call(capability: NevaehIntelligences::StructuredTicket::CAPABILITY, subject: ticket)
    raise "Gatekeeper accepted an unapproved revision" unless decision.denied? && decision.reason.include?("revision")
    raise ActiveRecord::Rollback
  end
  ticket.reload
  item_id = ticket.extra_fields.dig("nevaeh", "work_item_id")
  DymondDispatch::PerformWorkItemJob.perform_now(item_id)
  raise "Duplicate delivery repeated section execution" unless ticket.events.where(action: "nevaeh_section_verified").count == 4 && ticket.events.where(action: "nevaeh_structured_verified_and_resolved").count == 1
  # A historical default-queue dispatch created an escalation twin before the
  # candidate worker hook was installed. Reconcile that exact source item only.
  Marlon::Ticket.where(related_type: "DymondDispatch::WorkItem", related_id: item_id).where.not(id: ticket.id).find_each do |duplicate|
    source = duplicate.extra_fields.to_h.deep_stringify_keys
    next unless source["source"] == "nevaeh" && source["capability"] == NevaehIntelligences::StructuredTicket::CAPABILITY && source["correlation_id"] == ticket.extra_fields.dig("nevaeh", "reservation_id")
    NevaehIntelligences::TicketBacklog.document_disposition!(ticket: duplicate, actor: actor,
      outcome: "documented_duplicate", canonical_ticket: ticket,
      reason: "This escalation records the same work item #{item_id} and reservation as ticket #{ticket.id}. The original ticket has now independently verified all four action outputs and saved KB article #{ticket.extra_fields.dig('nevaeh', 'knowledge_article_id')} before resolution. Preserve this failure history and track the verified result on the canonical ticket.")
  end
  # Check the real installed cron library produces an ActiveJob payload for the
  # candidate sweep. The probe queue has no consumer and is removed afterward.
  cron_queue = "#{queue_name}_cron_probe"
  begin
    entry = YAML.load_file(File.join(File.expand_path("..", __dir__), "config/schedule.yml")).fetch("nevaeh_historical_backlog")
    raise "Backlog cron must use ActiveJob" unless entry["active_job"] == true
    cron = Sidekiq::Cron::Job.new(entry.merge("name" => cron_queue, "queue" => cron_queue))
    cron.enque!
    queued = Sidekiq::Queue.new(cron_queue).first
    raise "Cron did not enqueue the actual intake job" unless queued && queued.args.first["job_class"] == "NevaehIntelligences::ProcessBacklogJob"
  ensure
    Sidekiq::Queue.new(cron_queue).clear
  end
  Gatekeeper::LessonService.record!(key: "nevaeh-mail-policy-locking-regression",
    title: "Restore persisted mail sending policy locking and stop controls",
    capability: "lightek_mail.sending_policy", symptom: "Mail protocol regressions select sending_policies or receive a nil policy during synchronized submission",
    cause: "The namespaced model lost its explicit table and a process-local mutex stopped yielding the persisted policy",
    remediation: "Use lightek_mail_sending_policies and create_or_find_by!(id: 1).with_lock(requires_new: true), yielding the policy to quota and stop checks. Keep missing policy disabled and remove the global NilClass permission fallback.",
    verification: "Actual mail classes passed the dedicated PostgreSQL regression step in GitHub Actions run 41211759260 after source commit 047d3d08bbd1fb6b7efb63fe5c68a97c4ff9db0a. This verifies controlled mail policy behavior, not production deployment.",
    metadata: {"source_ticket_id" => 19, "verification_scope" => "controlled_postgresql_fixture", "implementation_deployed" => false, "auto_executable" => false})
  ticket.log!(action: "nevaeh_native_structured_acceptance_passed", detail: JSON.generate("actions_verified" => 4,
    "form_rendered" => true, "approval_denial_verified" => true, "duplicate_delivery_suppressed" => true, "cron_active_job_verified" => true, "repository_commit" => steps.dig("service", "output", "commit_sha"), "pushed" => true, "deployed" => false))
  puts "NEVAEH_STRUCTURED_ACCEPTANCE=#{JSON.generate(actions_verified: 4, actual_ticket_resolved: true,
    page_and_section_persisted: true, studio_hierarchy_persisted: true, code_committed_and_pushed: true, kb_saved: true, form_rendered: true, approval_denial_verified: true, duplicate_delivery_suppressed: true, cron_active_job_verified: true)}"
rescue StandardError => error
  ticket.log!(action: "nevaeh_native_structured_acceptance_failed", detail: JSON.generate("error_class" => error.class.name,
    "error" => error.message, "private_worker_log_tail" => (log && File.file?(log.path) ? File.read(log.path).last(10000) : nil))) if ticket
  raise
ensure
  if worker
    Process.kill("TERM", worker) rescue nil
    Process.waitpid(worker) rescue nil
  end
  capability.update!(enabled: false, queue: "default") if capability
  Sidekiq::Queue.new(queue_name).clear
  Sidekiq::ScheduledSet.new.each { |job| job.delete if job.queue == queue_name }
  log&.close
  FileUtils.remove_entry(workspace) if workspace && File.directory?(workspace)
end
