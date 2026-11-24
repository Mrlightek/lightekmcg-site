# frozen_string_literal: true

module ItServices
  # Completion is a technician claim until the customer confirms it.
  class Completion
    def self.submit!(request:, actor:, summary:)
      raise ArgumentError, "Active assigned technician required" unless actor&.persisted? && actor.access_active?
      raise ArgumentError, "Completion evidence must be 20-4000 characters" unless summary.to_s.strip.length.between?(20, 4000)
      request.with_lock do
        raise ArgumentError, "Only the assigned technician can submit completion" unless request.technician_id == actor.id
        raise ArgumentError, "Accepted work required" unless request.status == "in_progress"
        ticket = ticket_for!(request)
        ticket.with_lock do
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          handoff = fields.fetch("it_services_handoff", {})
          raise ArgumentError, "Accepted dispatch or customer-requested rework required" unless %w[accepted rework_requested].include?(handoff["state"]) &&
            handoff["technician_id"] == actor.id && handoff["reservation_id"] == request.reservation_id &&
            handoff.dig("payment_clearance", "reservation_id") == request.reservation_id
          work_log = Array(fields["it_services_work_log"])
          relevant = work_log.select do |entry|
            entry["technician_id"] == actor.id &&
              (handoff["state"] != "rework_requested" ||
                (handoff["customer_responded_at"].present? &&
                  Time.iso8601(entry["recorded_at"]) > Time.iso8601(handoff["customer_responded_at"])))
          end
          latest_verification = relevant.reverse.find { |entry| entry["step"] == "verification" }
          latest_repair = relevant.reverse.find { |entry| entry["step"] == "repair" }
          verified = latest_verification && latest_verification["result"] == "passed" &&
            (latest_repair.nil? ||
              Time.iso8601(latest_verification["recorded_at"]) >= Time.iso8601(latest_repair["recorded_at"]))
          if request.delivery_mode == "remote"
            verified &&= latest_verification["remote_preflight"].is_a?(Hash) &&
              latest_verification["remote_preflight"]["device_id"] == request.network_managed_device_id
          end
          raise ArgumentError, "Record a passing post-repair verification after the latest work or rework" unless verified
          handoff.merge!("state" => "pending_customer_confirmation", "completion_summary" => summary.strip,
            "completed_by_id" => actor.id, "submitted_at" => Time.current.iso8601(6))
          fields["it_services_handoff"] = handoff
          ticket.update!(extra_fields: fields)
          ticket.log!(action: "it_services_completion_submitted", detail: summary.strip, actor: actor)
          request.update!(status: "awaiting_customer", resolution_notes: summary.strip)
          ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: "in_progress",
            to_status: "awaiting_customer", note: "Technician submitted completion evidence for customer confirmation")
        end
      end
      request
    end

    def self.confirm!(request:, actor:, confirmed:, note:)
      raise ArgumentError, "Request owner must confirm" unless actor&.persisted? &&
        actor.access_active? && actor.id == request.user_id
      raise ArgumentError, "Choose confirmed or needs_more_work" unless %w[confirmed needs_more_work].include?(confirmed)
      raise ArgumentError, "Enter a response (1-1500 characters)" unless note.to_s.strip.length.between?(1, 1500)
      request.with_lock do
        raise ArgumentError, "No completion awaiting confirmation" unless request.status == "awaiting_customer"
        ticket = ticket_for!(request)
        ticket.with_lock do
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          handoff = fields.fetch("it_services_handoff", {})
          raise ArgumentError, "Technician completion evidence missing" unless handoff["state"] == "pending_customer_confirmation" &&
            handoff["completion_summary"].present? &&
            handoff["completed_by_id"] == request.technician_id &&
            handoff["reservation_id"] == request.reservation_id &&
            handoff.dig("payment_clearance", "reservation_id") == request.reservation_id
          accepted = confirmed == "confirmed"
          new_status = accepted ? "resolved" : "in_progress"
          handoff.merge!("state" => accepted ? "customer_confirmed" : "rework_requested",
            "customer_response" => note.strip, "customer_responded_at" => Time.current.iso8601(6))
          fields["it_services_handoff"] = handoff
          ticket.update!(extra_fields: fields, status: accepted ? "resolved" : "in_progress",
            resolved_at: accepted ? Time.current : nil)
          ticket.log!(action: accepted ? "it_services_customer_confirmed" : "it_services_rework_requested",
            detail: note.strip, actor: actor)
          request.update!(status: new_status, closed_at: accepted ? Time.current : nil)
          ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: "awaiting_customer",
            to_status: new_status, note: "Customer #{accepted ? 'confirmed' : 'requested rework'}: #{note.strip}")
        end
      end
      request
    end

    def self.ticket_for!(request)
      Marlon::Ticket.where(related: request).where.not(status: "resolved")
        .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last ||
        raise(ArgumentError, "Open Nevaeh service ticket required")
    end
  end
end
