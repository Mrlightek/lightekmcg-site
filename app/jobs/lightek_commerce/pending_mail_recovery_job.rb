# frozen_string_literal: true
# Reuses the existing Gatekeeper deployment and its node; never allocates a new VPS.
module LightekCommerce
  class PendingMailRecoveryJob < ApplicationJob
    queue_as :default

    def perform(provisioning_request_id)
      request = ProvisioningRequest.find(provisioning_request_id)
      node = request.gatekeeper_node
      return unless node
      receipt = node.metadata.to_h["website_deployment"].to_h
      return unless receipt["mail_setup_status"] == "pending" || receipt["mail_registration_status"] == "pending"

      # Do not rerun the full website installer or overwrite an existing customer site.
      # A dedicated mailbox recovery operation must be executed through Gatekeeper
      # once its narrowly scoped SSH command and credential contract are available.
      Rails.logger.warn("[LightekMail] Mail recovery pending for node=#{node.id}; isolated mailbox recovery required")
    end
  end
end
