# frozen_string_literal: true

# Invoked by the existing deployment SSH identity in a separate Rails process.
# The installed app and its actual database/private engines supply the runtime;
# only candidate planning services are overlaid. No checkout, deployment, worker
# restart, credential change or financial operation is performed by this script.
require "json"

raise "Installed production runtime required" unless Rails.env.production?
root = File.expand_path("..", __dir__)
raise "Candidate must be separate from installed Rails root" if File.realpath(root) == File.realpath(Rails.root)
ENV["NEVAEH_BACKLOG_ENABLED"] = "1"
ENV.delete("NEVAEH_BACKLOG_ACTOR_ID")

{
  "NevaehIntelligences::GithubDevelopmentPlanV7a" => "app/services/nevaeh_intelligences/github_development_plan_v7a.rb",
  "NevaehIntelligences::TicketExecution" => "app/services/nevaeh_intelligences/ticket_execution.rb",
  "Gatekeeper::LessonService" => "app/services/gatekeeper/lesson_service.rb"
}.each do |constant, path|
  constant.constantize # Let the installed app's loader initialize its own constant first.
  load File.join(root, path)
end
load File.join(root, "app/services/nevaeh_intelligences/ticket_backlog.rb")

counts = Hash.new(0)
errors = 0
Marlon::Ticket.where.not(status: "resolved").find_each do |ticket|
  begin
    # Existing production enforcement must stay in force. Any receipt already
    # requiring execution/recovery is held for its installed recovery workflow.
    execution = ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh", {})
    if execution["execution_status"].present? || execution["work_item_id"].present?
      counts["held_existing_execution"] += 1
      next
    end
    outcome = NevaehIntelligences::TicketBacklog.process!(ticket: ticket)
    ticket.reload
    state = ticket.extra_fields.to_h.fetch("nevaeh_backlog")
    raise "Production planning unexpectedly dispatched" if outcome == "executing"
    raise "Planning unexpectedly resolved ticket" if ticket.status == "resolved"
    raise "Missing engineering plan" unless state["engineering_plan"].is_a?(Hash)
    raise "Escalation omitted blockers" unless state["blockers"].is_a?(Array) && state["blockers"].any?
    diagnostic = {}
    native_fields = ticket.extra_fields.to_h.deep_stringify_keys
    source = native_fields.fetch("gatekeeper", {})
    if source["operation_id"].present?
      operation = GatekeeperOperation.find_by(id: source["operation_id"])
      if operation
        diagnostic["gatekeeper_operation"] = {
          "id" => operation.id, "status" => operation.status,
          "error_class" => operation.error_class, "error_message" => operation.error_message,
          "exit_status" => operation.exit_status, "output_tail" => operation.output.to_s.last(6000),
          "result" => operation.result.to_h.slice("github_run_id", "github_run_url", "deployed_sha", "http_status")
        }
      end
    end
    # The historical dispatcher puts its receipt number in this fixed title.
    # This lookup is read-only, never an instruction to invoke the named handler.
    if (match = /\AWorkItem failed.*\(#(\d+)\)\z/.match(ticket.title))
      item = DymondDispatch::WorkItem.find_by(id: match[1])
      if item
        diagnostic["work_item"] = {"id" => item.id, "status" => item.status,
          "handler" => item.handler, "error" => item.error.to_s.last(3000)}
        media_handlers = %w[DymondCompute::TrimHandler DymondCompute::TimelineRenderHandler DymondCompute::BlenderRenderHandler]
        if media_handlers.include?(item.handler)
          klass = item.handler.constantize
          target = if klass.respond_to?(:perform)
            klass.method(:perform)
          elsif klass.respond_to?(:call)
            klass.method(:call)
          else
            klass.instance_method(:perform)
          end
          path, line = target.source_location
          if path && File.file?(path)
            diagnostic["handler_inspection"] = {"parameters" => target.parameters,
              "source_path" => path, "source_line" => line,
              "source_excerpt" => File.readlines(path)[[line - 5, 0].max, 140].to_a.join.byteslice(0, 14000)}
          end
        end
      end
    end
    if diagnostic.present?
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("nevaeh_backlog")
        if state["source_diagnostics"] != diagnostic
          state["source_diagnostics"] = diagnostic
          fields["nevaeh_backlog"] = state
          ticket.update!(extra_fields: fields)
          ticket.log!(action: "nevaeh_native_source_inspected", detail: JSON.generate(diagnostic))
        end
      end
    end
    counts[outcome] += 1
  rescue StandardError => error
    NevaehIntelligences::TicketBacklog.record_failure!(ticket: ticket, error: error)
    errors += 1
    # Do not publish ticket contents, credentials, logs or financial details in CI.
    warn "NEVAEH_NATIVE_TICKET_ERROR=#{error.class.name}"
  end
end
puts "NEVAEH_NATIVE_BACKLOG_ACCEPTANCE=#{JSON.generate(counts: counts, errors: errors, production_dispatch_enabled: false, full_lifecycle_accepted: false)}"
raise "Native backlog acceptance has #{errors} errors; inspect internal ticket evidence" unless errors.zero?
