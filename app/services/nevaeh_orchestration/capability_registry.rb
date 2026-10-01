# frozen_string_literal: true

module NevaehOrchestration
  class CapabilityRegistry
    class CapabilityNotFound < StandardError; end
    class CapabilityDisabled < StandardError; end

    def self.fetch!(slug)
      capability = NevaehCapability.find_by(slug: slug.to_s)

      raise CapabilityNotFound,
            "Nevaeh capability #{slug.inspect} is not registered" unless capability

      raise CapabilityDisabled,
            "Nevaeh capability #{slug.inspect} is disabled" unless capability.enabled?

      capability
    end

    def self.resolve(intent:)
      hint =
        if intent.respond_to?(:capability_hint)
          intent.capability_hint
        end

      return fetch!(hint) if hint.present?

      capability = NevaehCapability.enabled.find_by(
        intent_name: intent.name
      )

      return capability if capability

      raise CapabilityNotFound,
            "No capability resolves intent #{intent.name.inspect}"
    end

    def self.enabled
      NevaehCapability.enabled.order(:domain, :name)
    end
  end
end
