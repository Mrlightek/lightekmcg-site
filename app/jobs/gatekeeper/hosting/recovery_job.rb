module Gatekeeper
  module Hosting
    class RecoveryJob < ApplicationJob
      queue_as :default
      def perform
        GatekeeperApplicationLaunch.where(status: "queued").find_each { |launch| LaunchApplicationJob.perform_later(launch.id) }
        GatekeeperApplicationLaunch.where(status: "provisioning").where("updated_at < ?", 2.hours.ago).find_each do |launch|
          launch.with_lock do
            next unless launch.status == "provisioning" && launch.updated_at < 2.hours.ago
            launch.update!(status: "failed", error_message: "Installation worker stopped reporting; retry reuses this server and application.")
          end
        end
        GatekeeperApplicationLaunch.where(status: "ready").find_each do |launch|
          MailPortRequestJob.perform_later(launch.id) if launch.receipt["mail_port_status"] == "pending"
        end
        GatekeeperApplicationTemplate.where(build_status: "queued").where("updated_at < ?", 2.hours.ago).update_all(build_status: "failed", enabled: false)
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
