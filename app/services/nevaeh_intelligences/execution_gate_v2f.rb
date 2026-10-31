# frozen_string_literal: true
module NevaehIntelligences
  # Called immediately before the DymondDispatch handler. Applies only to the
  # Nevaeh-owned Studio project creation path; generic jobs are unchanged.
  class ExecutionGateV2f
    class Denied < StandardError; end
    CAPABILITY = "studio.project.create"
    HANDLER = "Studio::Workers::ProjectCreation"

    def self.guarded?(item)
      item.kind.to_s == CAPABILITY && item.handler.to_s == HANDLER
    end

    def self.require_allowed!(item)
      if item.kind.to_s == "ticket.structured.execute"
        StructuredExecution.authorize_item!(item)
        return true
      end
      return true unless guarded?(item)
      raise Denied, "Production execution disabled" if Rails.env.production?
      raise Denied, "Original ticket subject missing" unless item.subject_type == "Marlon::Ticket" && item.subject_id.present?
      ticket = Marlon::Ticket.find_by(id: item.subject_id)
      raise Denied, "Original ticket unavailable" unless ticket
      raise Denied, "Ticket resolved" if ticket.status == "resolved"
      data = ticket.extra_fields.to_h.deep_stringify_keys
      order = NevaehIntelligences::WorkOrder.validate!(data.fetch("nevaeh_work_order") { raise Denied, "Work order missing" })
      state = data.fetch("nevaeh", {})
      raise Denied, "Work order environment mismatch" unless order.dig("execution_policy", "environment") == Rails.env
      raise Denied, "Wrong intent" unless order["intent_key"] == CAPABILITY && order["work_type"] == "create"
      raise Denied, "Ticket reservation unavailable" unless state["execution_status"].in?(%w[dispatch_reserved dispatched])
      raise Denied, "Reservation/correlation mismatch" if state["reservation_id"].blank? || state["reservation_id"].to_s != item.correlation_id.to_s
      raise Denied, "Linked work item differs" if state["work_item_id"].present? && state["work_item_id"].to_s != item.id.to_s
      raise Denied, "Saved work order revision changed" unless state["work_order_sha256"].present? && state["work_order_sha256"] == NevaehIntelligences::TicketApproval.fingerprint(order)
      raise Denied, "Saved inputs revision changed" unless state["inputs_sha256"].present? && state["inputs_sha256"] == NevaehIntelligences::TicketApproval.fingerprint(order.fetch("inputs"))
      args = Array(item.args)
      raise Denied, "Handler argument mismatch" unless args.length == 2 && args[0] == "create" && args[1].to_h.deep_stringify_keys == order.fetch("inputs")
      actor = User.find_by(id: state["actor_id"])
      raise Denied, "Original actor no longer an employee" unless actor&.persisted? && actor.employee?
      decision = ::Gatekeeper.authorize_capability!(
        capability: CAPABILITY, subject: ticket,
        context: {
          "authorization_scope" => "nevaeh_ticket_dispatch_v2e",
          "inputs_sha256" => state.fetch("inputs_sha256"),
          "actor_id" => actor.id, "ticket_id" => ticket.id,
          "environment" => Rails.env,
          "work_order_sha256" => state.fetch("work_order_sha256")
        }
      )
      raise Denied, "Gatekeeper denied execution" unless decision.respond_to?(:allowed?) &&
        decision.allowed? && decision.respond_to?(:capability) &&
        decision.capability == CAPABILITY && decision.policy == "nevaeh_ticket_revision_bound"
      true
    rescue ::Gatekeeper::AuthorizationDenied => e
      raise Denied, "Gatekeeper denied execution: #{e.message}"
    rescue NevaehIntelligences::WorkOrder::Invalid => e
      raise Denied, "Invalid work order: #{e.message}"
    end
  end
end
