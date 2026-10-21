# frozen_string_literal: true

module NevaehIntelligences
  # Adds exact-match evidence only. No automatic YAML selection, approval or dispatch.
  module StudioCapabilityDraftMatchV7a
    class Rejected < StandardError; end
    module_function

    def attach(draft:, plan:, match:)
      raise Rejected, 'invalid draft' unless draft.is_a?(Hash) && draft['status'] == 'review_only'
      raise Rejected, 'invalid plan' unless plan.is_a?(Hash) && plan['status'] == 'planning_only'
      raise Rejected, 'invalid match evidence' unless match.is_a?(Hash)
      raise Rejected, 'required capability mismatch' unless match['required_capability'] == plan['required_capability']
      raise Rejected, 'invalid match basis' unless match['selection_basis'] == 'exact_declared_requirement_only'
      raise Rejected, 'invalid matching status' unless %w[not_found present_inactive_unverified present_active_unverified].include?(match['matching_status'])
      raise Rejected, 'matching must remain inert' unless match['execution_authorized'] == false && match['implementation_verified'] == false && match['release_approved'] == false && match['gatekeeper_authorization_required'] == true
      raise Rejected, 'unsafe draft' unless %w[gatekeeper_approved executable production_allowed].all? { |key| draft[key] == false }
      raise Rejected, 'unsafe plan' unless plan['execution_enabled'] == false && plan.dig('gatekeeper', 'production_execution_allowed') == false
      raise Rejected, 'ticket mismatch' unless draft['ticket_id'] == plan['ticket_id'] && draft['tracking_key'] == plan['tracking_key'] && draft['development_plan_fingerprint'] == plan['fingerprint']
      raise Rejected, 'missing enriched plan' unless draft['studio_capability_engineering_plan'].is_a?(Hash)
      result = Marshal.load(Marshal.dump(draft))
      result['studio_capability_exact_match'] = Marshal.load(Marshal.dump(match))
      result
    rescue TypeError, ArgumentError
      raise Rejected, 'non-serializable evidence'
    end
  end
end
