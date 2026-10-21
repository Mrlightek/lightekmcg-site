# frozen_string_literal: true

module NevaehIntelligences
  # Composes the existing ticket->development plan with STUDIO-203 discovery evidence.
  # Does not alter the original planner; does not persist, execute, or authorize anything.
  module StudioCapabilityEngineeringPlanV7a
    class Rejected < StandardError; end
    module_function

    def from_ticket(ticket:, capability_snapshot:, planner: GithubDevelopmentPlanV7a)
      raise Rejected, 'capability snapshot must be an Array' unless capability_snapshot.is_a?(Array)
      raise Rejected, 'planner contract missing' unless planner.respond_to?(:from_ticket)
      raw = planner.from_ticket(ticket: ticket)
      raise Rejected, 'invalid development plan' unless raw.is_a?(Hash)
      # Strictly preserve planning and execution policy before attaching discovery-only evidence.
      gatekeeper = raw['gatekeeper']
      unless raw['execution_enabled'] == false && gatekeeper.is_a?(Hash) &&
          gatekeeper['authorization_required'] == true &&
          gatekeeper['production_execution_allowed'] == false &&
          gatekeeper['human_release_approval_required'] == true
        raise Rejected, 'unsafe development plan policy'
      end
      resolution = raw['capability_resolution']
      unless resolution == 'unverified_requires_repository_and_registry_inspection'
        raise Rejected, 'unexpected capability resolution'
      end
      StudioCapabilityPlanResolutionV7a.attach(plan: raw, capability_snapshot: capability_snapshot)
    rescue StudioCapabilityPlanResolutionV7a::Rejected => error
      raise Rejected, "discovery evidence rejected: #{error.message}"
    end
  end
end
