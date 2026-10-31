module Gatekeeper
  module Hosting
    class RecoveryJob < ApplicationJob
      queue_as :default
      def perform
        GatekeeperHostedApplication.where(status: "queued").find_each { |app| ProvisionApplicationJob.perform_later(app.id) }
        GatekeeperHostedApplication.where(status: "provisioning").where("started_at < ?", 1.hour.ago).find_each do |app|
          app.with_lock do
            next unless app.status == "provisioning" && app.started_at && app.started_at < 1.hour.ago
            app.update!(status: "failed", error_message: "Setup worker stopped reporting; retry reconciles the same application.")
            app.gatekeeper_operation&.update!(status: "failed", error_class: "HostingWorkerTimeout",
              error_message: "Setup worker stopped reporting; inspect the server receipt.", completed_at: Time.current)
          end
        end
        ProvisioningRequest.where(destroy_approval_status: "approved", destroyed_at: nil).find_each do |request|
          data = request.metadata.to_h
          next unless data["delete_state"] == "queued" && data["delete_actor_id"]
          DeleteServerJob.perform_later(request.id, data.fetch("delete_actor_id"))
        end
      end
    end
  end
end
