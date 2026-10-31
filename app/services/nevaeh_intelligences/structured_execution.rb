# frozen_string_literal: true

module NevaehIntelligences
  module StructuredExecution
    module_function

    def authorize!(ticket:, context: {})
      raise StructuredTicket::Invalid, "Persisted ticket required" unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      fields = ticket.reload.extra_fields.to_h.deep_stringify_keys
      order = WorkOrder.read!(ticket: ticket)
      state = fields.fetch("nevaeh", {})
      authorization = fields.fetch("nevaeh_structured", {})
      actor = User.find_by(id: state["actor_id"])
      raise StructuredTicket::Invalid, "Ticket execution permission revoked" unless actor&.persisted? && Ability.new(actor).can?(:execute_nevaeh, ticket)
      raise StructuredTicket::Invalid, "Wrong structured work order" unless order["intent_key"] == StructuredTicket::CAPABILITY && order.dig("execution_policy", "environment") == Rails.env
      fingerprint = TicketApproval.fingerprint(order)
      raise StructuredTicket::Invalid, "Structured revision is not authorized" unless authorization["authorized_revision"] == fingerprint && authorization["authorized_actor_id"] == actor.id && state["work_order_sha256"] == fingerprint
      raise StructuredTicket::Invalid, "Execution reservation missing" unless state["reservation_id"].present?
      given_actor = context.to_h.deep_stringify_keys["actor"]
      if given_actor.present?
        raise StructuredTicket::Invalid, "Dispatch actor mismatch" unless given_actor["type"] == "User" && given_actor["id"].to_s == actor.id.to_s
      end
      StructuredTicket.compile(order.fetch("inputs").fetch("sections"))
      actor
    end

    def dispatch!(ticket:, actor:, explicit: false)
      StructuredTicket.registered!
      StructuredTicket.plan!(ticket: ticket)
      reservation = nil
      ticket.with_lock do
        raise StructuredTicket::Invalid, "Resolved ticket" if ticket.status == "resolved"
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        order = WorkOrder.read!(ticket: ticket)
        state = fields.fetch("nevaeh", {})
        if state["reservation_id"].present?
          return explicit ? resume!(ticket: ticket, actor: actor, explicit: true) : reconcile!(ticket: ticket)
        end
        raise StructuredTicket::Invalid, "Ticket execution permission required" unless actor&.persisted? && Ability.new(actor).can?(:execute_nevaeh, ticket)
        authorization = fields.fetch("nevaeh_structured")
        fingerprint = TicketApproval.fingerprint(order)
        if explicit
          authorization.merge!("authorized_actor_id" => actor.id, "authorized_revision" => fingerprint)
        end
        raise StructuredTicket::Invalid, "Awaiting operator approval" unless authorization["authorized_actor_id"] == actor.id && authorization["authorized_revision"] == fingerprint
        reservation = SecureRandom.uuid
        fields["nevaeh"] = {"intent_key" => StructuredTicket::CAPABILITY, "execution_status" => "dispatch_reserved",
          "reservation_id" => reservation, "correlation_id" => reservation, "actor_id" => actor.id,
          "work_order_sha256" => fingerprint, "reserved_at" => Time.current.iso8601}
        ticket.update!(status: "in_progress", extra_fields: fields)
        Gatekeeper.authorize_capability!(capability: StructuredTicket::CAPABILITY, subject: ticket,
          context: {"actor" => {"type" => "User", "id" => actor.id}})
      end
      payload = {"ticket_id" => ticket.id, "reservation_id" => reservation}
      receipt = Dispatch.call(intent_key: StructuredTicket::CAPABILITY, payload: payload, actor: actor,
        execute: true, correlation_id: reservation, ticket: ticket)
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        fields.fetch("nevaeh").merge!("work_item_id" => receipt.fetch("work_item_id"), "dispatch_receipt" => receipt)
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_structured_dispatched", detail: receipt.to_json, actor: actor)
      end
      ReconcileTicketJob.set(wait: 5.seconds, queue: NevaehCapability.find_by!(slug: StructuredTicket::CAPABILITY).queue).perform_later(ticket.id)
      receipt
    end

    def authorize_item!(item)
      raise StructuredTicket::Invalid, "Structured handler mismatch" unless item.handler == StructuredTicket::HANDLER && item.subject_type == "Marlon::Ticket"
      ticket = Marlon::Ticket.find(item.subject_id)
      actor = authorize!(ticket: ticket)
      state = ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh")
      expected = ["execute", {"ticket_id" => ticket.id, "reservation_id" => state.fetch("reservation_id")}]
      raise StructuredTicket::Invalid, "Structured work item binding mismatch" unless item.correlation_id == state["reservation_id"] && item.args == expected && (state["work_item_id"].blank? || state["work_item_id"].to_s == item.id.to_s)
      actor
    end

    def execute!(ticket:, reservation:)
      actor = Gatekeeper.authorize_capability!(capability: StructuredTicket::CAPABILITY, subject: ticket).then { authorize!(ticket: ticket) }
      state = ticket.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh")
      raise StructuredTicket::Invalid, "Reservation mismatch" unless state["reservation_id"] == reservation
      order = WorkOrder.read!(ticket: ticket)
      order.fetch("inputs").fetch("sections").each do |step|
        ticket.with_lock do
          Gatekeeper.authorize_capability!(capability: StructuredTicket::CAPABILITY, subject: ticket)
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          raise StructuredTicket::Invalid, "Work order revision changed during execution" unless TicketApproval.fingerprint(order) == fields.dig("nevaeh", "work_order_sha256")
          workflow = fields.fetch("nevaeh_structured")
          completed = workflow.fetch("steps")
          raise StructuredTicket::Invalid, "Dependency not verified" unless step["depends_on"].all? { |id| completed.dig(id, "status") == "verified" }
          inputs = step.fetch("inputs").transform_values do |value|
            match = value.is_a?(String) && StructuredTicket::REF.match(value)
            match ? completed.fetch(match[1]).fetch("output").fetch(match[2]) : value
          end
          receipt = completed[step["id"]]
          output = receipt ? receipt.fetch("output") : StructuredActions.perform(step["action"], inputs, actor: actor, ticket: ticket)
          StructuredActions.verify!(step["action"], inputs, output, actor: actor)
          unless receipt
            completed[step["id"]] = {"status" => "verified", "inputs" => inputs, "output" => output, "verified_at" => Time.current.iso8601}
            ticket.update!(extra_fields: fields)
            ticket.log!(action: "nevaeh_section_verified", detail: {"section_id" => step["id"], "action" => step["action"], "output" => output}.to_json)
          end
        end
      end
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        return {"verified" => true, "ticket_id" => ticket.id} if fields.dig("nevaeh", "execution_status") == "verified"
        completed = fields.fetch("nevaeh_structured").fetch("steps")
        order.fetch("inputs").fetch("sections").each do |step|
          receipt = completed.fetch(step["id"])
          StructuredActions.verify!(step["action"], receipt.fetch("inputs"), receipt.fetch("output"), actor: actor)
        end
        article = Gatekeeper::LessonService.record!(key: "nevaeh-structured-ticket-#{ticket.id}", title: "Verified structured procedure: #{ticket.title}",
          capability: StructuredTicket::CAPABILITY, symptom: ticket.title, cause: "Structured action request",
          remediation: JSON.generate(order.fetch("inputs")), verification: JSON.generate(completed),
          metadata: {"source_ticket_id" => ticket.id, "nevaeh_capability" => StructuredTicket::CAPABILITY, "auto_executable" => false})
        fields.fetch("nevaeh").merge!("execution_status" => "verified", "knowledge_article_id" => article.id, "verification" => {"sections" => completed, "verified_at" => Time.current.iso8601})
        fields["nevaeh_backlog"] = fields.fetch("nevaeh_backlog", {}).merge("status" => "verified_resolved", "blockers" => [], "implementation_verified" => true)
        ticket.update!(status: "resolved", resolved_at: Time.current, extra_fields: fields)
        ticket.log!(action: "nevaeh_structured_verified_and_resolved", detail: {"section_count" => completed.size, "knowledge_article_id" => article.id}.to_json)
      end
      {"verified" => true, "ticket_id" => ticket.id}
    end

    def resume!(ticket:, actor:, explicit: false)
      raise StructuredTicket::Invalid, "Ticket execution permission required" unless actor&.persisted? && Ability.new(actor).can?(:execute_nevaeh, ticket)
      StructuredTicket.plan!(ticket: ticket)
      item = nil
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        raise StructuredTicket::Invalid, "Resolved ticket" if ticket.status == "resolved"
        state = fields.fetch("nevaeh")
        workflow = fields.fetch("nevaeh_structured")
        order = WorkOrder.read!(ticket: ticket)
        raise StructuredTicket::Invalid, "Saved revision changed; new approval required" unless state["work_order_sha256"] == TicketApproval.fingerprint(order)
        matches = DymondDispatch::WorkItem.where(subject_type: "Marlon::Ticket", subject_id: ticket.id,
          kind: StructuredTicket::CAPABILITY, correlation_id: state["reservation_id"]).to_a
        raise StructuredTicket::Invalid, "Ambiguous execution receipt" unless matches.one?
        item = matches.first
        raise StructuredTicket::Invalid, "Work item is not retryable" unless %w[failed error dead queued].include?(item.status.to_s)
        count = workflow.fetch("retry_count", 0)
        raise StructuredTicket::Invalid, "Retry limit reached; engineering review required" if count >= (explicit ? 5 : 2)
        if explicit
          state["actor_id"] = actor.id
          workflow.merge!("authorized_actor_id" => actor.id, "authorized_revision" => state["work_order_sha256"])
        end
        workflow["retry_count"] = count + 1
        ticket.update!(extra_fields: fields)
        Gatekeeper.authorize_capability!(capability: StructuredTicket::CAPABILITY, subject: ticket)
        item.update!(status: "queued", error: nil)
        ticket.log!(action: "nevaeh_structured_resumed", detail: {"work_item_id" => item.id, "retry" => count + 1}.to_json, actor: actor)
      end
      DymondDispatch::PerformWorkItemJob.set(queue: item.queue).perform_later(item.id)
      {"work_item_id" => item.id}
    end

    def reconcile!(ticket:)
      fields = ticket.reload.extra_fields.to_h.deep_stringify_keys
      state = fields.fetch("nevaeh", {})
      return "resolved" if ticket.status == "resolved" && state["execution_status"] == "verified"
      return "awaiting_approval" if fields.dig("nevaeh_structured", "authorized_revision").blank?
      matches = DymondDispatch::WorkItem.where(subject_type: "Marlon::Ticket", subject_id: ticket.id,
        kind: StructuredTicket::CAPABILITY, correlation_id: state["reservation_id"]).to_a
      raise StructuredTicket::Invalid, "Structured dispatch receipt requires review" unless matches.one?
      item = matches.first
      authorize_item!(item)
      unless state["work_item_id"]
        ticket.with_lock do
          data = ticket.extra_fields.to_h.deep_stringify_keys
          data.fetch("nevaeh")["work_item_id"] = item.id
          ticket.update!(extra_fields: data)
        end
      end
      if %w[failed error dead cancelled].include?(item.status.to_s)
        ticket.log!(action: "nevaeh_structured_execution_failed", detail: item.error.to_s) unless ticket.events.where(action: "nevaeh_structured_execution_failed", detail: item.error.to_s).exists?
        begin
          resume!(ticket: ticket, actor: User.find(state.fetch("actor_id")))
          return "pending"
        rescue StructuredTicket::Invalid
          ticket.with_lock do
            data = ticket.extra_fields.to_h.deep_stringify_keys
            data["nevaeh_backlog"] = data.fetch("nevaeh_backlog", {}).merge("status" => "escalated", "blockers" => [item.error.to_s.presence || "Structured execution failed; retry limit reached"])
            ticket.update!(extra_fields: data)
          end
          return "failed"
        end
      end
      "pending"
    end
  end
end
