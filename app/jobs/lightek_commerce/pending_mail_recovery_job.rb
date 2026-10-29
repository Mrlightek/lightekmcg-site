# frozen_string_literal: true
# Mail repair operates on the existing customer node, never provisioning a second VPS.
module LightekCommerce
  class PendingMailRecoveryJob < ApplicationJob
    queue_as :default

    def perform(provisioning_request_id)
      request = ProvisioningRequest.find(provisioning_request_id)
      node = request.gatekeeper_node
      return unless node
      receipt = node.metadata.to_h["website_deployment"].to_h
      return unless %w[pending].include?(receipt["mail_setup_status"]) ||
                    %w[pending].include?(receipt["mail_registration_status"])

      # Preserve the existing customer VPS and fail visibly until the scoped
      # remote recovery executor is installed. No website redeployment occurs.
      raise "Mail recovery requires an isolated Gatekeeper SSH operation for node #{node.id}"
    end
  end
end
