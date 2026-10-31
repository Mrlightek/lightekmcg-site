module Gatekeeper
  module Fleet
    class DispatchJob < ApplicationJob
      queue_as :default
      def perform(rollout_id)
        rollout = GatekeeperRollout.find(rollout_id)
        Rollouts.dispatch!(rollout)
        return unless rollout.status == "running"
        rollout.gatekeeper_update_targets.where(status: "queued").find_each do |target|
          UpdateJob.perform_later(target.id)
        end
      end
    end
  end
end
