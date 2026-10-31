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

require "net/http"
require "open3"
Rails.application.eager_load!
http = Net::HTTP.start("lightekmcg.com", 443, use_ssl: true, open_timeout: 10, read_timeout: 30) do |connection|
  connection.get("/up")
end
revision, _revision_error, revision_status = Open3.capture3("git", "rev-parse", "HEAD", chdir: Rails.root.to_s)
working_tree, _tree_error, tree_status = Open3.capture3("git", "status", "--porcelain", chdir: Rails.root.to_s)
_runtime_output, _runtime_error, worker_status = Open3.capture3("systemctl", "is-active", "--quiet", "lightekmcg-site-sidekiq")
runtime_evidence = {
  "verified_at" => Time.current.iso8601, "eager_load_passed" => true,
  "https_health_status" => http.code.to_i, "sidekiq_service_active" => worker_status.success?,
  "installed_revision" => revision_status.success? ? revision.strip : nil,
  "tracked_worktree_clean" => tree_status.success? && working_tree.lines.none? { |line| !line.start_with?("??") },
  "git_objects_writable" => File.writable?(Rails.root.join(".git/objects")),
  "lockfile_writable" => File.writable?(Rails.root.join("Gemfile.lock")),
  "mail_controller_loaded" => !!defined?(Api::LightekMailController),
  "system_logs_controller_loaded" => !!defined?(Dashboard::SystemLogsController),
  "mail_sending_policy_loaded" => !!defined?(LightekMail::SendingPolicy)
}
counts = Hash.new(0)
errors = 0
Marlon::Ticket.where.not(status: "resolved").find_each do |ticket|
  begin
    # Existing production enforcement must stay in force. Any receipt already
    # requiring execution/recovery is held for its installed recovery workflow.
    if ticket.extra_fields.to_h.dig("nevaeh_work_order", "intent_key") == "ticket.structured.execute"
      counts["handled_by_structured_acceptance"] += 1
      next
    end
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
    diagnostic = {"runtime_verification" => runtime_evidence}
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
        if item.handler == "DymondBank::AchChargeHandler" && ticket.related_type == "DymondBank::Invoice"
          invoice = ticket.related
          diagnostic["invoice_inspection"] = {"record_exists" => !!invoice}
          if invoice
            diagnostic["invoice_inspection"]["state"] = invoice.attributes.slice("id", "status", "payment_status", "paid_at", "processor", "payment_processor")
            diagnostic["invoice_inspection"]["associations"] = invoice.class.reflect_on_all_associations.map(&:name)
          end
        end
        if media_handlers.include?(item.handler)
          binary = DymondCompute.configuration.blender_path.to_s
          binary_exists = if binary.include?(File::SEPARATOR)
            File.executable?(binary)
          else
            ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, binary)) }
          end
          diagnostic["blender_binary_available"] = binary_exists
          diagnostic["media_arguments"] = item.args
          diagnostic["registered_media_capabilities"] = NevaehCapability.where(handler: item.handler)
            .map { |capability| {"slug" => capability.slug, "enabled" => capability.enabled?, "subject_type" => capability.subject_type} }
          implementation = {
            "DymondCompute::TrimHandler" => ["DymondCompute::Transcoding::TrimPipeline", :trim],
            "DymondCompute::TimelineRenderHandler" => ["DymondCompute::Transcoding::TimelineRenderer", :render],
            "DymondCompute::BlenderRenderHandler" => ["DymondCompute::Transcoding::BlenderRenderer", :render]
          }.fetch(item.handler)
          if item.handler == "DymondCompute::BlenderRenderHandler"
            builder = "DymondCompute::Transcoding::BlenderCommand".constantize.method(:build)
            builder_path, = builder.source_location
            diagnostic["command_builder_source"] = File.read(builder_path).byteslice(0, 14000) if builder_path && File.file?(builder_path)
            scene = DymondStudio::BlenderScene.find_by(id: Array(item.args).first)
            diagnostic["original_input"] = {"record_exists" => !!scene, "source_attached" => !!scene&.asset&.file&.attached?}
          elsif item.handler == "DymondCompute::TrimHandler"
            asset = DymondCompute::Asset.find_by(id: Array(item.args).first)
            diagnostic["original_input"] = {"record_exists" => !!asset, "source_attached" => !!asset&.file&.attached?}
          elsif item.handler == "DymondCompute::TimelineRenderHandler"
            timeline = DymondStudio::Timeline.find_by(id: Array(item.args).first)
            diagnostic["original_input"] = {"record_exists" => !!timeline}
          end
          renderer = implementation.first.constantize.method(implementation.last)
          renderer_path, renderer_line = renderer.source_location
          if renderer_path && File.file?(renderer_path)
            diagnostic["renderer_inspection"] = {"source_path" => renderer_path, "source_line" => renderer_line,
              "source_excerpt" => File.read(renderer_path).byteslice(0, 26000)}
          end
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
    historical_boot_incidents = {
      "40505481628" => {"component" => "mail_controller_loaded", "cause" => "Mail API skipped a nonexistent authentication callback",
        "remediation" => "Keep the API endpoint authentication contract explicit; do not skip callbacks that the controller does not define. Verify installed Rails eager loading, HTTPS health and worker readiness."},
      "40517519802" => {"component" => "system_logs_controller_loaded", "cause" => "Dashboard class was reopened using module syntax",
        "remediation" => "Use the qualified Dashboard::SystemLogsController declaration with the existing DymondDash controller contract. Verify installed Rails eager loading, HTTPS health and worker readiness."},
      "40542424744" => {"component" => "mail_sending_policy_loaded", "cause" => "Mail sending policy contained a Ruby syntax error",
        "remediation" => "Use the installed syntactically valid LightekMail::SendingPolicy definition. Verify eager loading of the actual application, HTTPS health and worker readiness before closing the incident."}
    }
    if source["operation_id"].present?
      original = GatekeeperOperation.find_by(id: source["operation_id"])
      run_id = original&.result.to_h["github_run_id"].to_s
      incident = historical_boot_incidents[run_id]
      if incident && runtime_evidence[incident.fetch("component")] == true
        actor = ticket.events.where.not(actor_id: nil).order(created_at: :desc).first&.actor
        proof = runtime_evidence.merge("component_verified" => true, "component" => incident.fetch("component"),
          "original_github_run_id" => run_id, "verification_mode" => "existing_deployed_implementation",
          "historical_revision_superseded" => true)
        outcome = NevaehIntelligences::TicketExecution.resolve_existing_deployment!(ticket: ticket, actor: actor,
          operation: original, verification: proof, cause: incident.fetch("cause"), remediation: incident.fetch("remediation"))
      end
    end
    if source["operation_id"].present? && ticket.status != "resolved"
      original = GatekeeperOperation.find_by(id: source["operation_id"])
      run_id = original&.result.to_h["github_run_id"].to_s
      dispositions = {
        "36436334079" => {"outcome" => "documented_obsolete", "canonical_operation" => nil,
          "reason" => "Historical failed attempt was superseded by a successful rerun of the same GitHub workflow run 36436334079. GitHub job 108980216173 is completed/success. Preserve the original failed GatekeeperOperation as attempt history; this is an obsolete failed-attempt escalation, not a new production repair."},
        "40234039223" => {"outcome" => "documented_duplicate", "canonical_operation" => 60,
          "reason" => "Both GitHub deployment jobs 121297960409 and 121297899216 failed at the same repository object-write permission boundary on October 25. Consolidate the shared Git ownership investigation under the ticket for GatekeeperOperation 60; retain both distinct failed operation receipts. No deployment was replayed."},
        "41158468767" => {"outcome" => "documented_duplicate", "canonical_operation" => 137,
          "reason" => "Both GitHub jobs 124410417754 and 124409541256 completed deployment with HTTPS 200, then failed the paid-installation acceptance command because LightekCommerce::Order id 1 did not exist. Consolidate that same post-deployment acceptance investigation under the ticket for GatekeeperOperation 137; retain both operation histories. This does not declare paid installation verified."}
      }
      disposition = dispositions[run_id]
      if disposition
        actor = ticket.events.where.not(actor_id: nil).order(created_at: :desc).first&.actor
        canonical = if disposition["canonical_operation"]
          Marlon::Ticket.find_by(related_type: "GatekeeperOperation", related_id: disposition["canonical_operation"])
        end
        outcome = NevaehIntelligences::TicketBacklog.document_disposition!(ticket: ticket, actor: actor,
          outcome: disposition.fetch("outcome"), reason: disposition.fetch("reason"), canonical_ticket: canonical)
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
