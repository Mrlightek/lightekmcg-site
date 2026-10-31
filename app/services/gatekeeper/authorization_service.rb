# frozen_string_literal: true

module Gatekeeper
  class AuthorizationService
    def self.call(capability:, subject: nil, context: {})
      new(
        capability: capability,
        subject: subject,
        context: context
      ).call
    end

    def initialize(capability:, subject: nil, context: {})
      @capability_name = capability.to_s
      @subject = subject
      @context = context.to_h.deep_stringify_keys
    end

    def call
      capability = capability_record

      return deny(
        "Capability is not registered with Nevaeh."
      ) unless capability

      return deny(
        "Capability is disabled."
      ) unless capability.enabled?

      if context["authorization_scope"] != "nevaeh_ticket_dispatch_v2e" && subject &&
         capability.subject_type.present? &&
         subject.class.name != capability.subject_type

        return deny(
          "Subject type #{subject.class.name.inspect} does not satisfy " \
          "#{capability.subject_type.inspect}."
        )
      end

      if capability_name == "ticket.structured.execute"
        begin
          NevaehIntelligences::StructuredExecution.authorize!(ticket: subject, context: context)
          return allow(policy: "structured_ticket_revision_bound", reason: "Authorized operator, saved structured revision, environment and execution reservation verified")
        rescue NevaehIntelligences::WorkOrder::Invalid, ActiveRecord::RecordNotFound => error
          return deny(error.message)
        end
      end

      # Dedicated Gatekeeper policy; Nevaeh retains capability ownership.
      # This scope may authorize an audit entry only, never dispatch or retry.
      if context["authorization_scope"] == "nevaeh_recovery_audit_v2f"
        return deny("Recovery policy disabled in production.") if Rails.env.production?
        return deny("Recovery requires persisted ticket.") unless @subject.is_a?(Marlon::Ticket) && @subject.persisted?
        return deny("Invalid recovery capability.") unless capability_name == "studio.project.create"
        return deny("Incompatible subject type.") if capability.subject_type.present? && capability.subject_type != "Marlon::Ticket"
        return deny("Ticket context mismatch.") unless context["ticket_id"].to_s == @subject.id.to_s
        return deny("Environment mismatch.") unless context["environment"] == Rails.env
        actor = User.find_by(id: context["actor_id"])
        return deny("Administrator required.") unless actor&.persisted? && %w[admin super_admin].include?(actor.role)
        return deny("Ticket permission denied.") unless Ability.new(actor).can?(:update, @subject)
        return deny("Invalid audit disposition.") unless %w[hold_for_review acknowledge_evidence].include?(context["action"])
        state = @subject.reload.extra_fields.to_h.deep_stringify_keys.fetch("nevaeh", {})
        reservation = state["reservation_id"].to_s
        return deny("Reservation mismatch.") if reservation.blank? || context["reservation_id"].to_s != reservation
        evidence = NevaehIntelligences::RecoveryEvidenceV2f.for_ticket(@subject)
        return deny("Evidence reservation mismatch.") unless evidence["reservation_id"].to_s == reservation
        return deny("Retries cannot be authorized.") unless evidence["automatic_retry_allowed"] == false
        classification = evidence["classification"].to_s
        return deny("Recovery evidence is not actionable.") if classification.blank? || classification == "queued"
        return deny("Evidence changed.") unless context["classification"] == classification
        return allow(policy: "nevaeh_recovery_audit_v2f", reason: "Verified administrator, ticket, reservation, current evidence and audit-only disposition.")
      end

      # Explicit Nevaeh ticket enforcement, not the generic capability fallback.
      if context["authorization_scope"] == "nevaeh_ticket_dispatch_v2e"
        return deny("Ticket subject is required.") unless subject.is_a?(Marlon::Ticket) && subject.persisted?
        return deny("Capability subject contract is incompatible with ticket dispatch.") if capability.subject_type.present? && capability.subject_type != "Marlon::Ticket"
        actor = User.find_by(id: context["actor_id"])
        return deny("A permitted, persisted actor is required.") unless actor&.employee? && Ability.new(actor).can?(:update, subject)
        return deny("Ticket context does not match subject.") unless context["ticket_id"].to_s == subject.id.to_s
        return deny("Environment mismatch.") unless context["environment"] == Rails.env && !Rails.env.production?
        stored = subject.extra_fields.to_h.deep_stringify_keys["nevaeh_work_order"]
        return deny("Saved Work Order is missing.") unless stored.is_a?(Hash)
        revision = NevaehIntelligences::TicketApproval.fingerprint(stored)
        return deny("Work Order revision mismatch.") unless context["work_order_sha256"] == revision
        inputs = stored["inputs"]
        return deny("Inputs revision mismatch.") unless inputs.is_a?(Hash) && context["inputs_sha256"] == NevaehIntelligences::TicketApproval.fingerprint(inputs)
        return deny("Unverified ticket capability.") unless capability_name == "studio.project.create" && stored["intent_key"] == capability_name && stored["work_type"] == "create"
        return allow(policy: "nevaeh_ticket_revision_bound", reason: "Actor, ticket, capability, environment and persisted revision verified.")
      end

      allow(
        policy: "registered_enabled_capability",
        reason:
          "Capability is registered, enabled, and satisfies its subject contract."
      )
    end

    private

    attr_reader :capability_name, :subject, :context

    def capability_record
      @capability_record ||=
        NevaehCapability.find_by(
          gatekeeper_capability: capability_name
        ) ||
        NevaehCapability.find_by(
          slug: capability_name
        )
    end

    def allow(policy:, reason:)
      AuthorizationDecision.new(
        allowed: true,
        capability: capability_name,
        reason: reason,
        correlation_id: context["correlation_id"],
        policy: policy,
        context: context
      )
    end

    def deny(reason)
      AuthorizationDecision.new(
        allowed: false,
        capability: capability_name,
        reason: reason,
        correlation_id: context["correlation_id"],
        policy: "deny",
        context: context
      )
    end
  end
end
