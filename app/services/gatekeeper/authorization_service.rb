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

      if subject &&
         capability.subject_type.present? &&
         subject.class.name != capability.subject_type

        return deny(
          "Subject type #{subject.class.name.inspect} does not satisfy " \
          "#{capability.subject_type.inspect}."
        )
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
