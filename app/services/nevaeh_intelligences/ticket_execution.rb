# frozen_string_literal: true

module NevaehIntelligences
  class TicketExecution
    class InvalidTicket < StandardError; end
    PROOF_CAPABILITY = "studio.project.create"
    AUTOMATIC_ACCEPTANCE_CRITERIA = [
      "Project and production persisted",
      "Studio project, production, and default scene persist with the requested project name"
    ].freeze

    def self.backlog_acceptance_supported?(order)
      criteria = order.to_h["acceptance_criteria"]
      criteria.is_a?(Array) && criteria.any? && criteria.all? { |criterion| AUTOMATIC_ACCEPTANCE_CRITERIA.include?(criterion) }
    end

    # Reserve the ticket under a database row lock BEFORE contacting the queue.
    # The reservation is committed first, preventing concurrent enqueue requests.
    # A failed/unknown dispatch is intentionally not auto-retried: the work may
    # have reached the queue even if the caller never received its receipt.
    def self.dispatch!(ticket:, actor:, payload:)
      raise InvalidTicket, "Authenticated employee/admin User required" unless actor.is_a?(User) && actor.persisted? && actor.employee?
      raise InvalidTicket, "Persisted ticket required" unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      raise InvalidTicket, "Production execution is not enabled" if Rails.env.production?
      inputs = payload.to_h.deep_stringify_keys
      raise InvalidTicket, "Project name is required" if inputs["name"].to_s.strip.empty?

      reservation = SecureRandom.uuid
      ticket.with_lock do
        data = ticket.extra_fields.to_h.deep_stringify_keys
        order = NevaehIntelligences::WorkOrder.validate!(data.fetch("nevaeh_work_order") { raise InvalidTicket, "Saved work order required" })
        raise InvalidTicket, "Work order environment mismatch" unless order.dig("execution_policy", "environment") == Rails.env
        raise InvalidTicket, "Work order executor is not verified" unless order["work_type"] == "create" && order["intent_key"] == PROOF_CAPABILITY
        raise InvalidTicket, "Dispatch payload differs from saved work order" unless inputs == order.fetch("inputs")
        raise InvalidTicket, "Ticket must be persisted and unresolved" unless ticket.persisted? && ticket.status != "resolved"
        raise InvalidTicket, "Only Studio project creation is verified for V1" unless data.dig("nevaeh_work_order", "intent_key") == PROOF_CAPABILITY
        state = data.fetch("nevaeh", {})
        raise InvalidTicket, "Ticket already reserved or executed" if state["execution_status"].present? || state["work_item_id"].present?
        # Fail closed before persisting a reservation or contacting DymondDispatch.
        begin
          NevaehIntelligences::GatekeeperWorkOrderAuthorization.require_allowed!(
            ticket: ticket, actor: actor, order: order, payload: inputs
          )
        rescue NevaehIntelligences::GatekeeperWorkOrderAuthorization::Denied => error
          raise InvalidTicket, "Gatekeeper denied Nevaeh dispatch: #{error.message}"
        end
        state = state.merge("intent_key" => PROOF_CAPABILITY,
          "execution_status" => "dispatch_reserved", "reservation_id" => reservation,
          "reserved_at" => Time.current.iso8601, "expected_project_name" => inputs.fetch("name"), "actor_id" => actor.id, "work_order_sha256" => NevaehIntelligences::TicketApproval.fingerprint(order), "inputs_sha256" => NevaehIntelligences::TicketApproval.fingerprint(inputs)) # V2F_EXECUTION_GATE
        data["nevaeh"] = state
        ticket.update!(status: "in_progress", extra_fields: data)
        ticket.log!(action: "nevaeh_dispatch_reserved", detail: {reservation_id: reservation}.to_json, actor: actor)
      end

      begin
        receipt = NevaehIntelligences::Dispatch.call(intent_key: PROOF_CAPABILITY,
          actor: actor, execute: true, payload: inputs, correlation_id: reservation, ticket: ticket)
      rescue StandardError => error
        ticket.with_lock do
          data = ticket.extra_fields.to_h.deep_stringify_keys
          state = data.fetch("nevaeh", {})
          if state["reservation_id"] == reservation && state["execution_status"] == "dispatch_reserved"
            state["execution_status"] = "dispatch_uncertain"
            state["error"] = "#{error.class}: #{error.message}".truncate(1500)
            data["nevaeh"] = state
            ticket.update!(extra_fields: data)
            ticket.log!(action: "nevaeh_dispatch_uncertain", detail: state["error"], actor: actor)
          end
        end
        raise
      end

      ticket.with_lock do
        data = ticket.extra_fields.to_h.deep_stringify_keys
        state = data.fetch("nevaeh", {})
        raise InvalidTicket, "Dispatch reservation changed; manual reconciliation required" unless state["reservation_id"] == reservation && state["execution_status"] == "dispatch_reserved"
        state.merge!("work_item_id" => receipt.fetch("work_item_id"),
          "correlation_id" => receipt.fetch("correlation_id"),
          "dispatch_receipt" => receipt, "execution_status" => "dispatched")
        data["nevaeh"] = state
        ticket.update!(extra_fields: data)
        ticket.log!(action: "nevaeh_dispatched", detail: receipt.to_json, actor: actor)
      end
      NevaehIntelligences::ReconcileTicketJob.set(wait: 10.seconds).perform_later(ticket.id)
      receipt
    end

    # Existing deployed fixes can satisfy historical incidents without rerunning
    # an obsolete deployment. Verification comes from the installed-app CI runner;
    # the original failed operation remains unchanged for audit.
    def self.resolve_existing_deployment!(ticket:, actor:, operation:, verification:, cause:, remediation:)
      raise InvalidTicket, "Authorized resolution operator required" unless actor.is_a?(User) && actor.persisted? && Ability.new(actor).can?(:resolve, ticket)
      raise InvalidTicket, "Original failed deployment required" unless operation.is_a?(GatekeeperOperation) && operation.persisted? && operation.capability == "deploy_project" && operation.status == "failed"
      proof = verification.to_h.deep_stringify_keys
      unless proof["eager_load_passed"] == true && proof["https_health_status"] == 200 &&
          proof["sidekiq_service_active"] == true && proof["installed_revision"].to_s.match?(/\A[0-9a-f]{40}\z/) &&
          proof["component_verified"] == true && proof["original_github_run_id"].to_s == operation.result.to_h["github_run_id"].to_s &&
          proof["original_github_run_id"].present?
        raise InvalidTicket, "Installed implementation acceptance evidence is incomplete"
      end
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("nevaeh", {})
        return "resolved" if ticket.status == "resolved" && state["execution_status"] == "verified"
        raise InvalidTicket, "Ticket already executing" if state["execution_status"].present? || state["work_item_id"].present?
        raise InvalidTicket, "Original incident mismatch" unless fields.dig("gatekeeper", "operation_id").to_s == operation.id.to_s
        order = WorkOrder.read!(ticket: ticket)
        raise InvalidTicket, "Original work order mismatch" unless order["work_type"] == "fix" && order.dig("inputs", "operation_id").to_s == operation.id.to_s
        article = ::Gatekeeper::LessonService.record!(
          key: "nevaeh-deployment-ticket-#{ticket.id}-verified", title: "Verified deployment recovery: #{cause}",
          capability: "deploy_project", symptom: ticket.description.to_s, cause: cause,
          remediation: remediation, verification: JSON.generate(proof),
          metadata: {"source_ticket_id" => ticket.id, "source_operation_id" => operation.id,
            "nevaeh_capability" => "deploy_project", "auto_executable" => false})
        state.merge!("execution_status" => "verified", "intent_key" => order["intent_key"],
          "verification_mode" => "existing_deployed_implementation", "verification" => proof,
          "work_order_sha256" => TicketApproval.fingerprint(order), "knowledge_article_id" => article.id)
        fields["nevaeh"] = state
        fields["nevaeh_backlog"] = fields.fetch("nevaeh_backlog", {}).merge(
          "status" => "verified_resolved", "blockers" => [], "implementation_verified" => true,
          "updated_at" => Time.current.iso8601)
        ticket.update!(status: "resolved", resolved_at: Time.current, extra_fields: fields)
        ticket.log!(action: "nevaeh_existing_implementation_verified", detail: JSON.generate(proof), actor: actor)
        "resolved"
      end
    end

    def self.reconcile!(ticket:)
      ticket.with_lock do
        data = ticket.extra_fields.to_h.deep_stringify_keys
        state = data.fetch("nevaeh", {})
        raise InvalidTicket, "No linked work item" unless state["work_item_id"].present?
        item = DymondDispatch::WorkItem.find(state.fetch("work_item_id"))
        raise InvalidTicket, "Wrong capability" unless item.kind == PROOF_CAPABILITY
        raise InvalidTicket, "Correlation mismatch" unless item.correlation_id.to_s == state.fetch("correlation_id").to_s

        return "resolved" if ticket.status == "resolved" && state["execution_status"] == "verified"
        return "failed" if state["execution_status"] == "failed" && item.status.to_s.in?(%w[failed error dead cancelled])
        return "verification_failed" if state["execution_status"] == "verification_failed" && item.status.to_s == "done"
        status = item.status.to_s
        case status
        when "done"
          result = item.result.to_h.deep_stringify_keys
          project = StudioProject.find_by(id: result["project_id"])
          production = Production.find_by(id: result["production_id"], studio_project_id: project&.id)
          scene = StudioScene.find_by(id: result["default_scene_id"], studio_project_id: project&.id, production_id: production&.id)
          verified = result["mutation"] == "created" && project && production && scene &&
            project.name == state["expected_project_name"] &&
            result.values_at("project_persisted", "production_persisted", "scene_persisted").all? { |v| v == true }
          if data["nevaeh_backlog"].present?
            order = WorkOrder.validate!(data.fetch("nevaeh_work_order"))
            verified &&= backlog_acceptance_supported?(order) &&
              state["work_order_sha256"] == TicketApproval.fingerprint(order) &&
              state["inputs_sha256"] == TicketApproval.fingerprint(order.fetch("inputs")) &&
              item.subject_type == "Marlon::Ticket" && item.subject_id == ticket.id
          end
          unless verified
            state["execution_status"] = "verification_failed"
            state["verification"] = {"work_item_status" => status, "result" => result}
            data["nevaeh"] = state
            ticket.update!(extra_fields: data)
            ticket.log!(action: "nevaeh_verification_failed", detail: state["verification"].to_json)
            return "verification_failed"
          end
          state["execution_status"] = "verified"
          state["verification"] = {"project_id" => project.id, "production_id" => production.id,
            "scene_id" => scene.id, "work_item_id" => item.id,
            "correlation_id" => item.correlation_id, "verified_at" => Time.current.iso8601}
          if data["nevaeh_backlog"].present?
            article = ::Gatekeeper::LessonService.record!(
              key: "nevaeh-ticket-#{ticket.id}-verified", title: "Verified solution: #{ticket.title}",
              capability: PROOF_CAPABILITY, symptom: ticket.description.presence || ticket.title,
              cause: "Ticket requested Studio project creation through the registered capability",
              remediation: "Use the existing #{PROOF_CAPABILITY} work order through Nevaeh and Gatekeeper",
              verification: JSON.generate(state.fetch("verification")),
              metadata: {"source_ticket_id" => ticket.id, "nevaeh_capability" => PROOF_CAPABILITY,
                "work_order_sha256" => state["work_order_sha256"], "auto_executable" => false})
            state["knowledge_article_id"] = article.id
          end
          data["nevaeh"] = state
          ticket.update!(status: "resolved", resolved_at: Time.current, extra_fields: data)
          ticket.log!(action: "nevaeh_verified_and_resolved", detail: state["verification"].to_json)
          "resolved"
        when "failed", "error", "dead", "cancelled"
          state["execution_status"] = "failed"
          state["error"] = item.error.to_s.truncate(1500)
          data["nevaeh"] = state
          ticket.update!(extra_fields: data)
          ticket.log!(action: "nevaeh_execution_failed", detail: {"work_item_id" => item.id, "error" => state["error"]}.to_json)
          "failed"
        else
          "pending"
        end
      end
    end
  end
end
