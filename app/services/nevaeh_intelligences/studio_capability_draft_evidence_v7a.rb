# frozen_string_literal: true

module NevaehIntelligences
  # STUDIO-203: evidence-only attachment to an existing ticket/capability draft.
  # Never authorizes execution or infers a capability key from a ticket.
  module StudioCapabilityDraftEvidenceV7a
    class Rejected < StandardError; end
    module_function

    def attach(draft:, original_plan:, enriched_plan:)
      raise Rejected, 'invalid draft' unless draft.is_a?(Hash) && draft['status'] == 'review_only'
      raise Rejected, 'invalid plans' unless original_plan.is_a?(Hash) && enriched_plan.is_a?(Hash)
      raise Rejected, 'ticket mismatch' unless draft['ticket_id'] == original_plan['ticket_id'] && enriched_plan['ticket_id'] == original_plan['ticket_id']
      raise Rejected, 'tracking mismatch' unless draft['tracking_key'] == original_plan['tracking_key'] && enriched_plan['tracking_key'] == original_plan['tracking_key']
      raise Rejected, 'plan fingerprint mismatch' unless draft['development_plan_fingerprint'] == original_plan['fingerprint']
      [original_plan, enriched_plan].each do |plan|
        raise Rejected, 'not planning-only' unless plan['status'] == 'planning_only'
        raise Rejected, 'unsafe execution policy' unless plan['execution_enabled'] == false && plan.dig('gatekeeper', 'production_execution_allowed') == false
      end
      %w[gatekeeper_approved executable production_allowed].each do |flag|
        raise Rejected, 'unsafe draft flag' unless draft[flag] == false
      end
      # Keep existing record structure intact, adding only a deep copied, inert plan.
      result = Marshal.load(Marshal.dump(draft))
      result['studio_capability_engineering_plan'] = Marshal.load(Marshal.dump(enriched_plan))
      result['gatekeeper_approved'] = false
      result['executable'] = false
      result['production_allowed'] = false
      result
    rescue TypeError, ArgumentError
      raise Rejected, 'non-serializable or invalid evidence'
    end
  end
end
