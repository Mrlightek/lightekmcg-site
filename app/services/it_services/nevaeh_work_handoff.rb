# frozen_string_literal: true

module ItServices
  # Human technician work stays on the existing Marlon ticket and is visible to
  # Nevaeh's backlog. Do not impersonate a DymondDispatch::WorkItem: the latter
  # requires a published, Gatekeeper-authorized executable capability.
  class NevaehWorkHandoff
    class Invalid < StandardError; end

    def self.record!(request:, actor:, note:, payment_receipt:)
      raise Invalid, "Authorized operations actor required" unless actor&.persisted? &&
        actor.role == "super_admin" && actor.access_active?
      ticket = Marlon::Ticket.where(related: request).where.not(status: "resolved")
        .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last
      raise Invalid, "An open Nevaeh IT Services ticket is required" unless ticket
      raise Invalid, "Request must be scheduled" unless request.status == "scheduled"
      raise Invalid, "Assigned technician required" unless request.technician_id.present?
      raise Invalid, "Linked reservation required" unless request.reservation_id.present?

      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        state = fields.fetch("it_services_handoff", {})
        if state["reservation_id"] == request.reservation_id &&
            state["technician_id"] == request.technician_id && state["state"] == "scheduled"
          return state
        end
        receipt = {
          "state" => "scheduled",
          "request_id" => request.id,
          "technician_id" => request.technician_id,
          "reservation_id" => request.reservation_id,
          "actor_id" => actor.id,
          "payment_clearance" => payment_receipt,
          "recorded_at" => Time.current.iso8601(6)
        }
        fields["it_services_handoff"] = receipt
        ticket.update!(status: "in_progress", extra_fields: fields)
        ticket.log!(action: "it_services_human_dispatch", detail: note.to_s.truncate(1500), actor: actor)
        receipt
      end
    end
  end
end
