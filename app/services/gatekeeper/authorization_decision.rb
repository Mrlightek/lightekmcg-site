# frozen_string_literal: true

module Gatekeeper
  class AuthorizationDecision
    attr_reader \
      :allowed,
      :capability,
      :reason,
      :correlation_id,
      :policy,
      :context

    def initialize(
      allowed:,
      capability:,
      reason:,
      correlation_id: nil,
      policy: nil,
      context: {}
    )
      @allowed = !!allowed
      @capability = capability.to_s
      @reason = reason.to_s
      @correlation_id = correlation_id.to_s.presence
      @policy = policy.to_s.presence
      @context = context.to_h.deep_stringify_keys
    end

    def allowed?
      allowed
    end

    def denied?
      !allowed?
    end

    def to_h
      {
        allowed: allowed?,
        capability: capability,
        reason: reason,
        correlation_id: correlation_id,
        policy: policy,
        context: context
      }.compact
    end
  end
end
