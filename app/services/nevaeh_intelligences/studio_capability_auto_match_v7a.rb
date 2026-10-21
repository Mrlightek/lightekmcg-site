# frozen_string_literal: true

module NevaehIntelligences
  # Deterministic evidence-only matching of an explicitly declared capability
  # requirement against STUDIO-203 discovery. No prose/LLM inference and no dispatch.
  module StudioCapabilityAutoMatchV7a
    class Rejected < StandardError; end
    MAX_ENTRIES = 1000
    KEY = /\A[a-z][a-z0-9_.-]*\z/
    module_function

    def resolve(plan:, capability_snapshot:)
      raise Rejected, 'invalid plan' unless plan.is_a?(Hash)
      gate = plan['gatekeeper']
      unless plan['status'] == 'planning_only' && plan['execution_enabled'] == false &&
             gate.is_a?(Hash) && gate['authorization_required'] == true &&
             gate['production_execution_allowed'] == false && gate['human_release_approval_required'] == true
        raise Rejected, 'unsafe planning policy'
      end
      key = plan['required_capability']
      raise Rejected, 'invalid required capability' unless key.is_a?(String) && KEY.match?(key)
      raise Rejected, 'invalid snapshot' unless capability_snapshot.is_a?(Array) && capability_snapshot.size <= MAX_ENTRIES
      seen = {}
      match = nil
      capability_snapshot.each do |raw|
        raise Rejected, 'invalid discovery entry' unless raw.is_a?(Hash)
        identifiers = [raw['key'], raw['slug'], raw[:key], raw[:slug]].compact
        raise Rejected, 'ambiguous discovery identifiers' unless identifiers.length.between?(1, 2) && identifiers.uniq.length == 1
        id = identifiers.first
        raise Rejected, 'invalid discovery identifier' unless id.is_a?(String) && KEY.match?(id)
        raise Rejected, 'duplicate discovery identifier' if seen.key?(id)
        seen[id] = true
        # A disabled or unpublished capability is still discoverable metadata,
        # never an executable permission. Flag values must be literal booleans.
        %w[enabled published].each do |flag|
          if raw.key?(flag) && raw[flag] != true && raw[flag] != false
            raise Rejected, 'invalid discovery status flag'
          end
        end
        if id == key
          match = { 'enabled' => raw['enabled'] == true, 'published' => raw['published'] == true }
        end
      end
      status = if match.nil?
                 'not_found'
               elsif !match['enabled'] || !match['published']
                 'present_inactive_unverified'
               else
                 'present_active_unverified'
               end
      {
        'schema_version' => 1,
        'required_capability' => key,
        'matching_status' => status,
        'registry_presence_only' => !match.nil?,
        'implementation_verified' => false,
        'execution_authorized' => false,
        'gatekeeper_authorization_required' => true,
        'release_approved' => false,
        'selection_basis' => 'exact_declared_requirement_only',
        'candidate_count' => match.nil? ? 0 : 1
      }.freeze
    end
  end
end
