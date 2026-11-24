# frozen_string_literal: true

module ItServices
  # Records human-performed IT diagnostics and repair evidence. Never executes
  # commands against customer devices or treats a technician claim as proof.
  class TechnicianWork
    STEPS = {
      "intake" => "Confirm symptoms and reproduce the issue",
      "diagnosis" => "Record diagnostic observations and the affected system",
      "repair" => "Record repair or configuration actions actually performed",
      "verification" => "Record a post-repair test and observed result"
    }.freeze
    RESULTS = %w[passed failed inconclusive not_applicable].freeze
    REMOTE_DIAGNOSTIC_STEPS = %w[diagnosis verification].freeze

    def self.record!(request:, actor:, step:, result:, evidence:)
      raise ArgumentError, "Active assigned technician required" unless actor&.persisted? && actor.access_active?
      raise ArgumentError, "Unknown work step" unless STEPS.key?(step)
      raise ArgumentError, "Unknown result" unless RESULTS.include?(result)
      raise ArgumentError, "Describe observed evidence (20-4000 characters)" unless evidence.to_s.strip.length.between?(20, 4000)
      request.with_lock do
        raise ArgumentError, "Only assigned technician may record work" unless request.technician_id == actor.id
        raise ArgumentError, "Accept the appointment before recording work" unless request.status == "in_progress"
        ticket = Marlon::Ticket.where(related: request).where.not(status: "resolved")
          .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last
        raise ArgumentError, "Linked Nevaeh ticket required" unless ticket
        ticket.with_lock do
          fields = ticket.extra_fields.to_h.deep_stringify_keys
          handoff = fields.fetch("it_services_handoff", {})
          raise ArgumentError, "Accepted dispatch required" unless %w[accepted rework_requested].include?(handoff["state"]) &&
            handoff["technician_id"] == actor.id && handoff["reservation_id"] == request.reservation_id
          remote_preflight = if request.delivery_mode == "remote" && REMOTE_DIAGNOSTIC_STEPS.include?(step)
            RemoteDiagnosticAuthorization.verify!(request: request, technician: actor)
          end
          entries = Array(fields["it_services_work_log"])
          entry = {
            "step" => step, "result" => result, "evidence" => evidence.strip,
            "technician_id" => actor.id, "recorded_at" => Time.current.iso8601(6),
            "remote_preflight" => remote_preflight
          }
          raise ArgumentError, "Work log limit reached" if entries.size >= 100
          fields["it_services_work_log"] = entries + [entry]
          ticket.update!(extra_fields: fields)
          ticket.log!(action: "it_services_work_#{step}", detail: "#{result}: #{evidence.strip}".truncate(4000), actor: actor)
          ItServiceEvent.create!(it_service_request: request, actor: actor, from_status: request.status,
            to_status: request.status, note: "#{STEPS.fetch(step)}: #{result}. #{evidence.strip}".truncate(2000))
          entry
        end
      end
    end
  end
end
