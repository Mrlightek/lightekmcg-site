class ExecutiveDcpValidationJob < ApplicationJob
  self.enqueue_after_transaction_commit = true

  def perform(id)
    delivery = NevaehDcpDelivery.find(id)
    return unless delivery.status == 'pending' && !delivery.revoked_at? && delivery.expires_at.future?

    sha = delivery.package.blob.open { |file| NevaehOs::DcpPackage.inspect_file(file.path) }
    delivery.with_lock do
      return unless delivery.status == 'pending' && !delivery.revoked_at? && delivery.expires_at.future?

      delivery.update!(status: 'ready', sha256: sha)
      DymondDash::Notification.create!(recipient: delivery.recipient, subject: delivery, category: 'system',
        title: 'A theater screening package is ready',
        url: Rails.application.routes.url_helpers.dashboard_executive_dcp_delivery_path(delivery.key))
    end
  rescue ArgumentError => error
    delivery&.with_lock { delivery.update!(status: 'rejected', error: error.message) if delivery.status == 'pending' }
  end
end
