module Gatekeeper
  module Compute
    class ProviderSelector
      class NoEligibleProvider < StandardError; end

      def self.call(policy:)
        candidates = [policy.preferred_provider, policy.fallback_provider].compact.uniq
        provider = candidates.find do |candidate|
          next false unless candidate.status == "active"
          next false unless %w[healthy unknown].include?(candidate.health_status)
          Array(policy.required_capabilities).all? { |capability| candidate.capability?(capability) }
        end

        provider || raise(NoEligibleProvider, "No active provider satisfies compute policy #{policy.slug}")
      end
    end
  end
end
