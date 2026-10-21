# frozen_string_literal: true

require "digest"
require "json"

module NevaehIntelligences
  # V2E staging contract. No execution path calls this class yet.
  # Gatekeeper's currently deployed capability policy does not authenticate an
  # actor or bind approvals to ticket revisions; these checks stay here.
  class GatekeeperWorkOrderAuthorization
    class Denied < StandardError; end
    PROOF_CAPABILITY = "studio.project.create"

    def self.require_allowed!(ticket:, actor:, order:, payload:)
      raise Denied, "Authenticated employee required" unless actor.is_a?(User) && actor.persisted? && actor.employee?
      raise Denied, "Persisted ticket required" unless ticket.is_a?(Marlon::Ticket) && ticket.persisted?
      raise Denied, "Production execution disabled" if Rails.env.production?
      validated = NevaehIntelligences::WorkOrder.validate!(order)
      raise Denied, "Work order environment mismatch" unless validated.dig("execution_policy", "environment") == Rails.env
      raise Denied, "Unverified intent" unless validated["intent_key"] == PROOF_CAPABILITY && validated["work_type"] == "create"
      raise Denied, "Dispatch payload mismatch" unless payload.to_h.deep_stringify_keys == validated.fetch("inputs")
      persisted = ticket.reload.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh_work_order") { raise Denied, "Saved work order missing" }
      raise Denied, "Persisted work order differs" unless persisted == validated
      raise Denied, "Ticket is already executing" if ticket.status == "resolved" || ticket.extra_fields.to_h.deep_stringify_keys.dig("nevaeh", "execution_status").present?

      # Subject is the persisted ticket, not a project created later by dispatch.
      # Only Gatekeeper's real entrypoint qualifies; no Studio local allow fallback.
      decision = ::Gatekeeper.authorize_capability!(
        capability: PROOF_CAPABILITY,
        subject: ticket,
        context: {
          "authorization_scope" => "nevaeh_ticket_dispatch_v2e",
          "inputs_sha256" => NevaehIntelligences::TicketApproval.fingerprint(validated.fetch("inputs")),
          "actor_id" => actor.id,
          "ticket_id" => ticket.id,
          "environment" => Rails.env,
          "work_order_sha256" => NevaehIntelligences::TicketApproval.fingerprint(validated)
        }
      )
      raise Denied, "Gatekeeper returned no explicit matching allowance" unless
        decision.respond_to?(:allowed?) && decision.allowed? &&
        decision.respond_to?(:capability) && decision.capability == PROOF_CAPABILITY && decision.policy == "nevaeh_ticket_revision_bound"
      decision
    rescue ::Gatekeeper::AuthorizationDenied => error
      raise Denied, error.message
    rescue NevaehIntelligences::WorkOrder::Invalid => error
      raise Denied, error.message
    end
  end
end
