module Gatekeeper
  module Hosting
    class MailPortRequestJob < ApplicationJob
      queue_as :default
      retry_on StandardError, wait: 5.minutes, attempts: 6
      def perform(id)
        launch = GatekeeperApplicationLaunch.find(id)
        return unless launch.status == "ready" && launch.provisioning_request
        MailPortRequest.submit!(request: launch.provisioning_request, actor: launch.requested_by, domain: launch.domain)
        launch.update!(receipt: launch.receipt.except("mail_port_error").merge("mail_port_status" => "submitted"))
      end
    end
  end
end
