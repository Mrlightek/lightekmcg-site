# frozen_string_literal: true

# Applies only to Nevaeh Studio project creation; general DymondDispatch jobs
# still execute their original worker method. No automatic retry on a lost worker.
module NevaehV2fAtomicStudioPerform
  def perform(work_item_id)
    item = DymondDispatch::WorkItem.find_by(id: work_item_id)
    return super unless NevaehIntelligences::AtomicStudioClaimV2f.target?(item)
    return unless NevaehIntelligences::AtomicStudioClaimV2f.claim!(item.id, worker_id: send(:worker_id))

    item.reload
    begin
      result = send(:invoke, item) # Existing V2F Gatekeeper hook runs here.
      item.mark_done!(result.is_a?(Hash) ? result : { value: result.to_s })
    rescue StandardError => e
      item.mark_failed!("#{e.class}: #{e.message}")
      # Same Nevaeh-managed behavior as the reviewed dispatch worker: no
      # generic automatic escalation; the Nevaeh disposition handles tickets.
    end
    DymondDispatch::Dispositions.fire!(item)
    item
  end
end

Rails.application.config.to_prepare do
  worker = DymondDispatch::PerformWorkItemJob
  unless worker.ancestors.include?(NevaehV2fAtomicStudioPerform)
    worker.prepend(NevaehV2fAtomicStudioPerform)
  end
end
