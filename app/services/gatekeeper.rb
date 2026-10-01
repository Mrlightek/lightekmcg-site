# frozen_string_literal: true

module Gatekeeper
  class AuthorizationDenied < StandardError
    attr_reader :decision

    def initialize(decision)
      @decision = decision

      super(
        "Gatekeeper denied #{decision.capability.inspect}: " \
        "#{decision.reason}"
      )
    end
  end

  def self.authorize_capability!(
    capability:,
    subject: nil,
    context: {}
  )
    decision =
      AuthorizationService.call(
        capability: capability,
        subject: subject,
        context: context
      )

    raise AuthorizationDenied, decision if decision.denied?

    decision
  end
end
