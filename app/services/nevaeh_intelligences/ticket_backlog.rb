# frozen_string_literal: true

module NevaehIntelligences
  # Coordinates existing ticket planning/dispatch/reconciliation. All durable
  # state remains on Marlon::Ticket; DymondDispatch owns execution and recovery.
  class TicketBacklog
    MAX_FAILURES = 5
    RECOVERABLE = %w[queued working_or_interrupted completed_unverified terminal_failure_review].freeze

    def self.enabled?
      ENV.fetch("NEVAEH_BACKLOG_ENABLED", "1") == "1"
    end

    def self.process!(ticket:)
      new(ticket).process!
    end

    def initialize(ticket)
      @ticket = ticket
    end

    def process!
      return "disabled" unless self.class.enabled?
      return "resolved" if ticket.reload.status == "resolved"
      fields = ticket.extra_fields.to_h.deep_stringify_keys
      prior = fields.fetch("nevaeh_backlog", {})
      if prior.fetch("failure_count", 0) >= MAX_FAILURES && prior["failure_inputs_sha256"] == failure_fingerprint(fields)
        return "escalated"
      end
      execution = fields.fetch("nevaeh", {})
      return reconcile! if execution["execution_status"].present? || execution["work_item_id"].present?

      # Analysis is serialized separately from dispatch so TicketExecution commits
      # its reservation before contacting the queue, as its contract requires.
      ticket.with_lock do
        return "resolved" if ticket.status == "resolved"
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        execution = fields.fetch("nevaeh", {})
        return "executing" if execution["execution_status"].present? || execution["work_item_id"].present?
        analysis = analyze(fields)
        prior = fields.fetch("nevaeh_backlog", {})
        if prior["analysis_sha256"] == analysis["analysis_sha256"] && prior.fetch("failure_count", 0) >= MAX_FAILURES
          return "escalated"
        end
        if prior["analysis_sha256"] != analysis["analysis_sha256"]
          analysis["failure_count"] = 0
        else
          analysis["failure_count"] = prior.fetch("failure_count", 0)
        end
        save_analysis!(fields, analysis)
        return analysis.fetch("status") unless analysis["status"] == "ready"
      end
      actor = User.find_by(id: ENV["NEVAEH_BACKLOG_ACTOR_ID"])
      WorkOrder.dispatch!(ticket: ticket, actor: actor)
      record_state!("executing", [])
      "executing"
    rescue WorkOrder::Invalid, TicketExecution::InvalidTicket, Dispatch::Unavailable => error
      # A racing worker may already own the operation. Never release or retry its
      # reservation merely because another worker observed it.
      return reconcile! if ticket.reload.extra_fields.to_h.deep_stringify_keys.dig("nevaeh", "execution_status").present?
      record_state!("escalated", ["#{error.class}: #{error.message}"])
      "escalated"
    end

    def self.record_failure!(ticket:, error:)
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("nevaeh_backlog", {})
        count = state.fetch("failure_count", 0) + 1
        state.merge!("failure_count" => count, "failure_inputs_sha256" => failure_fingerprint(fields), "status" => count >= MAX_FAILURES ? "escalated" : "retry_pending",
          "blockers" => ["#{error.class}: #{error.message}".truncate(1500)], "updated_at" => Time.current.iso8601)
        fields["nevaeh_backlog"] = state
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_backlog_failure", detail: state.to_json)
        count
      end
    end

    def self.document_disposition!(ticket:, actor:, outcome:, reason:, canonical_ticket: nil)
      unless actor.is_a?(User) && actor.persisted? && Ability.new(actor).can?(:resolve, ticket)
        raise WorkOrder::Invalid, "Authorized resolution operator required"
      end
      raise WorkOrder::Invalid, "Invalid documented disposition" unless %w[documented_obsolete documented_duplicate].include?(outcome)
      raise WorkOrder::Invalid, "Documented reason required" if reason.to_s.strip.length < 50
      if outcome == "documented_duplicate" && (!canonical_ticket&.persisted? || canonical_ticket.id == ticket.id)
        raise WorkOrder::Invalid, "Distinct canonical ticket required"
      end
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("nevaeh", {})
        backlog = fields.fetch("nevaeh_backlog", {})
        return outcome if ticket.status == "resolved" && backlog["status"] == outcome
        if state["execution_status"].present? || state["work_item_id"].present?
          raise WorkOrder::Invalid, "Existing execution must be reconciled before disposition"
        end
        disposition = {"outcome" => outcome, "reason" => reason, "actor_id" => actor.id,
          "canonical_ticket_id" => canonical_ticket&.id, "documented_at" => Time.current.iso8601}
        fields["nevaeh_backlog"] = backlog.merge("status" => outcome, "blockers" => [],
          "disposition" => disposition, "implementation_verified" => false)
        ticket.update!(status: "resolved", resolved_at: Time.current, extra_fields: fields)
        ticket.log!(action: "nevaeh_#{outcome}", detail: disposition.to_json, actor: actor)
      end
      outcome
    end

    def self.failure_fingerprint(fields)
      TicketApproval.fingerprint({"fields" => fields.except("nevaeh_backlog")})
    end

    def self.resume!(ticket:)
      ticket.with_lock do
        raise WorkOrder::Invalid, "Resolved ticket cannot be resumed" if ticket.status == "resolved"
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("nevaeh_backlog", {})
        state.merge!("failure_count" => 0, "status" => "queued", "updated_at" => Time.current.iso8601)
        fields["nevaeh_backlog"] = state
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_backlog_resume_requested")
      end
      ProcessBacklogJob.perform_later(ticket_id: ticket.id)
    end

    private

    attr_reader :ticket

    def failure_fingerprint(fields)
      self.class.failure_fingerprint(fields)
    end

    def analyze(fields)
      if !fields.key?("nevaeh_work_order") && fields["required_capability"].present? &&
          fields["work_type"].present? && fields["acceptance_criteria"].is_a?(Array) &&
          fields["acceptance_criteria"].any? && fields["inputs"].is_a?(Hash)
        attributes = WorkOrder.template(work_type: fields["work_type"], intent_key: fields["required_capability"]).merge(
          "objective" => ticket.description.presence || ticket.title, "inputs" => fields["inputs"],
          "acceptance_criteria" => fields["acceptance_criteria"],
          "execution_policy" => {"environment" => Rails.env.to_s, "approval" => "gatekeeper"})
        WorkOrder.attach!(ticket: ticket, attributes: attributes)
        fields.replace(ticket.extra_fields.to_h.deep_stringify_keys)
      end
      unless fields.key?("nevaeh_work_order")
        incident = incident_work_order(fields)
        if incident
          WorkOrder.attach!(ticket: ticket, attributes: incident)
          fields.replace(ticket.extra_fields.to_h.deep_stringify_keys)
        end
      end
      order = fields["nevaeh_work_order"]
      order = WorkOrder.validate!(order) if order
      source = fields.fetch("gatekeeper", {}).to_h
      key = order&.fetch("intent_key") || fields["required_capability"] || source["capability"]
      capabilities = NevaehCapability.order(:id).map do |record|
        {"slug" => record.slug, "enabled" => record.enabled?, "handler" => record.handler,
          "gatekeeper_capability" => record.gatekeeper_capability, "updated_at" => record.updated_at&.iso8601(6)}
      end
      # Gatekeeper's native infrastructure registry predates Nevaeh's DB rows.
      # Include its real registrations as discovery metadata, never as approval.
      if defined?(::Gatekeeper::CapabilityRegistry)
        ::Gatekeeper::CapabilityRegistry::REGISTRY.each do |name, handler|
          next if capabilities.any? { |record| record["slug"] == name }
          capabilities << {"slug" => name, "enabled" => true, "handler" => handler,
            "registration_source" => "gatekeeper_native_registry"}
        end
      end
      aliases = capabilities.select { |record| record["gatekeeper_capability"] == key }
      key = aliases.first.fetch("slug") if aliases.one? && !capabilities.any? { |record| record["slug"] == key }
      related_ids = if source["capability"].present? && source["node_id"].present? && source["project_id"].present?
        Marlon::Ticket.where.not(id: ticket.id)
          .where("extra_fields->'gatekeeper'->>'capability' = ?", source["capability"])
          .where("extra_fields->'gatekeeper'->>'node_id' = ?", source["node_id"].to_s)
          .where("extra_fields->'gatekeeper'->>'project_id' = ?", source["project_id"].to_s)
          .order(:id).limit(100).pluck(:id)
      else
        []
      end
      # Do not silently treat a KB outage as "no known procedure".
      raise "Knowledge Base unavailable" unless defined?(DymondKb::Article) && DymondKb::Article.table_exists?
      articles = NevaehOrchestration::KnowledgeResolver.for(capability: key,
        additional_article_ids: fields.fetch("knowledge_article_ids", []))
      if source["capability"].present? && source["capability"] != key
        articles += NevaehOrchestration::KnowledgeResolver.for(capability: source["capability"])
        articles = articles.uniq(&:id).first(10)
      end
      if articles.empty? && ticket.title.present?
        articles = DymondKb::Article.search(ticket.title.to_s.first(240)).ordered.limit(5).to_a
        if articles.empty?
          topic = ticket.title.to_s.scan(/[[:alpha:]]+/).select { |word| word.length >= 4 }.first(2).join(" ")
          articles = DymondKb::Article.search(topic).ordered.limit(5).to_a if topic.split.length == 2
        end
      end
      plan = GithubDevelopmentPlanV7a.from_native_ticket(ticket: ticket,
        knowledge_article_ids: articles.map(&:id), capability_snapshot: capabilities,
        required_capability: key, source_evidence: source.slice("operation_id", "capability", "node_id", "project_id", "error_class", "error_message"))
      blockers = []
      dependencies = Array(fields["depends_on_ticket_ids"])
      if dependencies.any? { |id| !id.is_a?(Integer) || id <= 0 || id == ticket.id }
        blockers << "Invalid or self-referencing ticket dependency"
      else
        dependencies.each do |id|
          dependency = Marlon::Ticket.find_by(id: id)
          blockers << "Dependency ticket #{id} is missing or lacks verified resolution" unless
            dependency && dependency.status == "resolved" &&
              dependency.extra_fields.to_h.dig("nevaeh", "execution_status") == "verified"
        end
      end
      blockers << "Duplicate reference requires acceptance review: ticket #{fields['duplicate_of_ticket_id']}" if fields["duplicate_of_ticket_id"].present?
      blockers << "Saved work order and explicit acceptance criteria are required" unless order
      blockers << "Acceptance criteria are missing" if plan["acceptance_criteria"].empty?
      match = capabilities.find { |record| record["slug"] == key }
      blockers << "Capability #{key.inspect} is not registered and enabled" unless match && match["enabled"]
      unless order && order["intent_key"] == TicketExecution::PROOF_CAPABILITY && order["work_type"] == "create"
        blockers << "No verified ticket executor for this work type; repository implementation and acceptance review required"
      end
      if order && order["intent_key"] == TicketExecution::PROOF_CAPABILITY && !TicketExecution.backlog_acceptance_supported?(order)
        blockers << "Acceptance criteria require a verifier beyond the existing Studio persistence checks"
      end
      blockers << "Existing Gatekeeper ticket policy disables production execution" if Rails.env.production?
      actor = User.find_by(id: ENV["NEVAEH_BACKLOG_ACTOR_ID"])
      unless actor&.employee? && Ability.new(actor).can?(:execute_nevaeh, ticket)
        blockers << "NEVAEH_BACKLOG_ACTOR_ID must identify an authorized persisted operator"
      end
      input_digest = TicketApproval.fingerprint({"title" => ticket.title, "description" => ticket.description,
        "fields" => fields.except("nevaeh_backlog"), "capabilities" => capabilities,
        "knowledge" => articles.map { |a| [a.id, a.updated_at&.iso8601(6)] },
        "blockers" => blockers})
      {"status" => blockers.empty? ? "ready" : "escalated", "blockers" => blockers,
        "classification" => source["operation_id"].present? ? "operational_execution" : (order&.fetch("work_type") || "investigation"),
        "related_ticket_ids" => related_ids,
        "analysis_sha256" => input_digest, "engineering_plan" => plan,
        "knowledge_article_ids" => articles.map(&:id), "required_capability" => key,
        "implementation_verified" => false}
    end

    def incident_work_order(fields)
      source = fields.fetch("gatekeeper", {}).to_h
      if source["operation_id"].present? && source["capability"].present?
        inputs = source.slice("operation_id", "capability", "node_id", "project_id")
        key = source.fetch("capability")
        criteria = [
          "Identify the exact failed operation step and target revision from its persisted receipt",
          "Verify the requested target or explicitly document that a later verified deployment supersedes it",
          "Preserve application boot, HTTPS health and worker readiness evidence before resolution"
        ]
      elsif (match = /\AWorkItem failed.*\(#(\d+)\)\z/.match(ticket.title))
        item = DymondDispatch::WorkItem.find_by(id: match[1])
        return unless item
        inputs = {"original_work_item_id" => item.id, "handler" => item.handler}
        registration = NevaehCapability.find_by(handler: item.handler)
        key = registration&.slug || item.kind.to_s
        return if key.blank?
        criteria = case item.handler
        when "DymondCompute::TrimHandler"
          ["Verify the original source asset and trim interval", "Produce and validate the requested persisted trim artifact without closed-stream errors"]
        when "DymondCompute::TimelineRenderHandler"
          ["Verify the executing FFmpeg binary supports every filter used by the original timeline", "Render and inspect the requested timeline artifact including its text overlays"]
        when "DymondCompute::BlenderRenderHandler"
          ["Verify original scene, renderer exit status and expected output path", "Render and validate the requested output artifact before registering success"]
        when "DymondBank::AchChargeHandler"
          ["Reconcile the original invoice ledger against provider transfer history", "Verify the current authorized processor configuration", "Establish safe idempotent disposition of the original attempt before any financial replay"]
        else
          ["Inspect the original WorkItem arguments and its registered handler contract", "Verify the original requested outcome using persisted acceptance evidence"]
        end
      else
        return
      end
      WorkOrder.template(work_type: "fix", intent_key: key).merge(
        "objective" => ticket.description.presence || ticket.title,
        "inputs" => inputs, "acceptance_criteria" => criteria,
        "execution_policy" => {"environment" => Rails.env.to_s, "approval" => "gatekeeper",
          "execution_enabled" => false, "requires_human_release_approval" => true})
    end

    def save_analysis!(fields, analysis)
      prior = fields.fetch("nevaeh_backlog", {})
      %w[source_diagnostics job_receipts].each do |key|
        analysis[key] = prior[key] if prior.key?(key)
      end
      return if prior.except("updated_at") == analysis
      analysis["updated_at"] = Time.current.iso8601
      fields["nevaeh_backlog"] = analysis
      ticket.update!(extra_fields: fields)
      ticket.log!(action: "nevaeh_backlog_#{analysis.fetch('status')}", detail: analysis.to_json)
    end

    def reconcile!
      evidence = RecoveryEvidenceV2f.for_ticket(ticket)
      state = ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh", {})
      unless state["work_item_id"].present? && RECOVERABLE.include?(evidence["classification"])
        record_state!("escalated", ["Execution receipt requires recovery review: #{evidence['classification']}"])
        return "escalated"
      end
      outcome = TicketExecution.reconcile!(ticket: ticket)
      case outcome
      when "resolved" then record_state!("verified_resolved", [])
      when "pending" then record_state!("executing", [])
      else record_state!("escalated", ["Existing execution reconciliation returned #{outcome}"])
      end
      outcome
    end

    def record_state!(status, blockers)
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("nevaeh_backlog", {})
        return if state["status"] == status && state["blockers"] == blockers
        state.merge!("status" => status, "blockers" => blockers, "updated_at" => Time.current.iso8601)
        fields["nevaeh_backlog"] = state
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_backlog_#{status}", detail: state.to_json)
      end
    end
  end
end
