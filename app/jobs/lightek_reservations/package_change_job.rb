module LightekReservations
  class PackageChangeJob < ApplicationJob
    queue_as :default
    class Pending < StandardError; end
    retry_on Pending, wait: 2.minutes, attempts: 60
    def perform(change_id)
      change = Change.find(change_id)
      # A row lock serializes retries; provider state is reconciled before another
      # request, and entitlement changes wait for the running target plan.
      change.with_lock do
        return if change.status == 'applied'
        return unless %w[scheduled applying].include?(change.status) && change.effective_at <= Time.current
        raise Pending, 'Verified package payment required' unless change.order&.paid_at? && %w[paid fulfilled].include?(change.order.status)
        reservation = change.reservation
        raise Pending, 'Reservation is no longer active' unless %w[confirmed expired].include?(reservation.status)
        request = ProvisioningRequest.find(reservation.order.provisioning_request_id)
        node = request.gatekeeper_node || raise(Pending, 'Server allocation not ready')
        target = change.quote.fetch('target')
        adapter = node.compute_provider.adapter(requested_by: reservation.customer.email_address)
        unless adapter.is_a?(Gatekeeper::Compute::Providers::LinodeAdapter)
          raise Pending, 'This provider requires an operator to apply the package change'
        end
        state = adapter.node(node.provider_resource_id)
        plan = target.fetch('compute').fetch('plan')
        if state['type'] != plan
          adapter.resize_node(node.provider_resource_id, plan: plan) if %w[running offline].include?(state['status'])
          # Committing the observation before retry keeps an accepted provider
          # operation durable; no entitlement is changed by an empty API receipt.
          change.update!(status: 'applying', error: 'Waiting for the provider to confirm the target plan')
          self.class.set(wait: 2.minutes).perform_later(change.id)
          next
        end
        unless state['status'] == 'running'
          adapter.start_node(node.provider_resource_id) if state['status'] == 'offline'
          self.class.set(wait: 2.minutes).perform_later(change.id)
          next
        end
        reservation.with_lock do
          raise Pending, 'Package changed after this quote' unless reservation.package_snapshot == change.quote['original']
          attributes = {status: 'confirmed', resource: change.target_resource, package_snapshot: target}
          if change.quote['renewal']
            start = change.effective_at
            finish = target['billing_interval'] == 'annual' ? start + 1.year : start + 1.month
            attributes.merge!(starts_at: start, ends_at: finish, blocks_from: start, blocks_until: finish)
          end
          installation = GatekeeperInstallation.find_by!(gatekeeper_node: node, account: reservation.customer, component: 'lightek_app')
          raise Pending, 'A registered native Rails runtime is required' unless installation.adapter == 'native_rails'
          receipt = Gatekeeper::Fleet::Transport.run!(node: node, domain: installation.domain,
            requested_by: reservation.customer.email_address, operation_id: nil,
            script_name: 'sync_reservation.py', payload: {domain: installation.domain,
              owner_email: reservation.customer.email_address, reference: reservation.reference, change_id: change.id,
              package: target, starts_at: attributes.fetch(:starts_at, reservation.starts_at).iso8601,
              ends_at: attributes.fetch(:ends_at, reservation.ends_at).iso8601, deployment: installation.deployment_config})
          unless receipt['status'] == 'applied' && receipt['reference'] == reservation.reference && receipt['change_id'] == change.id
            raise Pending, 'Client package synchronization has not been verified'
          end
          reservation.update!(attributes)
          request.subscription.update!(status: 'active', plan_id: target.fetch('subscription_plan_id'),
            current_period_start: reservation.starts_at, current_period_end: reservation.ends_at)
          node.update!(metadata: node.metadata.to_h.merge('reservation_package' => target))
          change.update!(status: 'applied', error: nil)
          change.order.update!(status: 'fulfilled', fulfilled_at: Time.current)
        end
      end
    rescue Pending
      raise
    rescue StandardError => error
      change&.update!(status: 'failed', error: "#{error.class}: #{error.message}".first(1000))
      raise
    end
  end
end
