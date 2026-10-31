module Gatekeeper
  module Fleet
    class SweepJob < ApplicationJob
      queue_as :default
      def perform
        GatekeeperRollout.where(status: "draft", requested_by: "github_release_pipeline").find_each do |rollout|
          Releases.start_pending!(rollout)
        end
        GatekeeperRollout.where(status: %w[running paused canceled]).find_each do |rollout|
          rollout.with_lock do
            stale = rollout.gatekeeper_update_targets.where(status: "running").where("started_at < ?", 1.hour.ago)
            had_stale = stale.exists?
            stale.each do |target|
              target.gatekeeper_operation&.update!(status: "failed", error_class: "FleetWorkerTimeout",
                error_message: "Worker stopped reporting; inspect the remote receipt.", completed_at: Time.current)
              target.update!(status: rollout.status == "canceled" ? "canceled" : "failed",
                error_message: "Worker stopped reporting. Check the remote receipt before retrying.", completed_at: Time.current)
            end
            if had_stale && rollout.status == "running"
              rollout.update!(status: "paused", message: "A worker stopped reporting; inspect remote state before retrying.")
            end
          end
          DispatchJob.perform_later(rollout.id) if rollout.status == "running"
        end
      end
    end
  end
end
