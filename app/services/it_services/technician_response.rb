# frozen_string_literal: true

module ItServices
  # Human acceptance is an auditable service event, not an executable DymondDispatch job.
  class TechnicianResponse
    def self.call!(request:, actor:, decision:, note:)
      raise ArgumentError, "Sign in as the assigned technician" unless actor&.persisted? && actor.access_active?
      raise ArgumentError, "Choose accept or decline" unless %w[accept decline].include?(decision)
      raise ArgumentError, "Enter a reason (1-1500 characters)" unless note.to_s.strip.length.between?(1, 1500)

      request.with_lock do
        raise ArgumentError, "Only the assigned technician can respond" unless request.technician_id == actor.id
        raise ArgumentError, "Only scheduled work can be accepted or declined" unless request.status == "scheduled"
        ticket = Marlon::Ticket.where(related: request).where.not(status: "resolved")
          .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last
        raise ArgumentError, "Linked Nevaeh service ticket required" unless ticket
        ticket.with_lock do
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          handoff = fields.fetch("it_services_handoff", {})
          raise ArgumentError, "Dispatch handoff mismatch" unless handoff["state"] == "scheduled" &&
            handoff["technician_id"] == actor.id && handoff["reservation_id"] == request.reservation_id

          new_status = decision == "accept" ? "in_progress" : "triaged"
          handoff.merge!("state" => decision == "accept" ? "accepted" : "declined",
            "responded_at" => Time.current.iso8601(6), "response_note" => note.strip)
          fields["it_services_handoff"] = handoff
          ticket.update!(extra_fields: fields)
          ticket.log!(action: "it_services_technician_#{decision}", detail: note.strip, actor: actor)
          request.update!(status: new_status, technician: decision == "decline" ? nil : actor,
            technician_assigned_at: decision == "decline" ? nil : request.technician_assigned_at)
          ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: "scheduled",
            to_status: new_status, note: "Technician #{decision}: #{note.strip}")
        end
      end
      request
    end
  end
end
