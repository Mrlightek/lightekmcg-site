module LightekReservations
  # End of paid occupancy pauses compute after a three-day renewal grace period.
  # The node, application, and data remain allocated; no server is deleted.
  class ExpireServerJob < ApplicationJob
    queue_as :default
    def perform(id)
      reservation = Reservation.find(id)
      reservation.with_lock do
        return unless reservation.server? && reservation.status == 'confirmed' && reservation.ends_at + 3.days < Time.current
        paid_renewal = reservation.package_changes.where(status: %w[scheduled applying failed]).any? do |change|
          next false unless change.quote['renewal'] && change.order&.paid_at? && %w[paid fulfilled].include?(change.order.status)
          finish = change.quote.dig('target', 'billing_interval') == 'annual' ? change.effective_at + 1.year : change.effective_at + 1.month
          finish > Time.current
        end
        return if paid_renewal
        request = ProvisioningRequest.find_by(id: reservation.order&.provisioning_request_id)
        return unless request&.gatekeeper_node
        node = request.gatekeeper_node
        adapter = node.compute_provider.adapter(requested_by: 'reservation-expiry')
        state = adapter.node(node.provider_resource_id)
        if state['status'] == 'running'
          adapter.shutdown_node(node.provider_resource_id)
          self.class.set(wait: 2.minutes).perform_later(id)
        elsif state['status'] == 'offline'
          reservation.update!(status: 'expired')
          request.subscription.update!(status: 'past_due')
        else
          self.class.set(wait: 2.minutes).perform_later(id)
        end
      end
    end
  end
end
