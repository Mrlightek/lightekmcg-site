# frozen_string_literal: true

module NevaehIntelligences
  # Read-only evidence bridge between the engineering plan and STUDIO-203 discovery.
  # Does not authorize work, select a handler, dispatch jobs, or persist anything.
  module StudioCapabilityPlanResolutionV7a
    class Rejected < StandardError; end
    module_function

    def attach(plan:, capability_snapshot:)
      raise Rejected, 'plan must be a Hash' unless plan.is_a?(Hash)
      raise Rejected, 'capability snapshot must be an Array' unless capability_snapshot.is_a?(Array)
      required = plan.fetch('required_capability') { raise Rejected, 'required capability missing' }
      raise Rejected, 'invalid capability key' unless required.is_a?(String) && required.match?(/\A[a-z][a-z0-9_.-]*\z/)
      raise Rejected, 'capability list exceeds limit' if capability_snapshot.length > 1000

      matches = capability_snapshot.select do |entry|
        raise Rejected, 'invalid capability entry' unless entry.is_a?(Hash)
        key = entry['key'] || entry['slug'] || entry[:key] || entry[:slug]
        raise Rejected, 'invalid capability identifier' unless key.is_a?(String) && key.match?(/\A[a-z][a-z0-9_.-]*\z/)
        key == required
      end
      raise Rejected, 'duplicate capability identifier' if matches.length > 1
      status = matches.empty? ? 'not_found' : 'discovered_unverified'
      # Deliberately do not replace original capability_resolution or policy fields.
      evidence = {
        'required_capability' => required,
        'discovery_status' => status,
        'registry_presence_only' => !matches.empty?,
        'execution_authorized' => false,
        'gatekeeper_authorization_required' => true,
        'implementation_verified' => false,
        'release_approved' => false
      }.freeze
      result = plan.dup
      raise Rejected, 'existing evidence field' if result.key?('studio203_evidence')
      result['studio203_evidence'] = evidence
      result.freeze
    end
  end
end
