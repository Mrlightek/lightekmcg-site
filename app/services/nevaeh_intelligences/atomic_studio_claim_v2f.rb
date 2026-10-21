# frozen_string_literal: true

module NevaehIntelligences
  # Atomic claim for precisely the Nevaeh Studio project creation path.
  # A crash after claim leaves a 'working' item for manual reconciliation;
  # it must never trigger an automatic second Studio mutation.
  class AtomicStudioClaimV2f
    KIND = "studio.project.create"
    HANDLER = "Studio::Workers::ProjectCreation"

    def self.target?(item)
      item && item.kind.to_s == KIND && item.handler.to_s == HANDLER
    end

    def self.claim!(work_item_id, worker_id:)
      updated = DymondDispatch::WorkItem
        .where(id: work_item_id, kind: KIND, handler: HANDLER, status: "queued")
        .update_all([
          "status = ?, worker_id = ?, started_at = ?, attempts = COALESCE(attempts, 0) + 1",
          "working", worker_id, Time.current
        ])
      updated == 1
    end
  end
end
