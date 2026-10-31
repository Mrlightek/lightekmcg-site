# frozen_string_literal: true
module LightekCommerce
  module Installations
    def self.scope_for(actor, operator: false)
      scope = Order.joins(items: :product).where(lightek_commerce_products: {product_type: "lightek_instance"}).distinct
      return scope.where(customer_email: actor.email_address) unless operator
      return scope if actor.role == "super_admin"
      return scope.where(site_id: LightekSettings::WebsiteIdentity.sites_for(actor).select(:id)) if actor.role == "admin"
      scope.none
    end

    def self.can_manage_access?(actor, order)
      actor&.persisted? && (actor.role == "super_admin" || actor.email_address == order.customer_email)
    end

    def self.ready?(order)
      order.paid_at? && %w[paid fulfilled].include?(order.status) && order.provisioning_state == "ready" && order.provisioned_at?
    end

    def self.hostname(order)
      "client-#{order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}".downcase
    end

    def self.summary(order)
      request = ProvisioningRequest.find_by(id: order.provisioning_request_id)
      node = request&.gatekeeper_node
      state = if !order.paid_at? || !%w[paid fulfilled].include?(order.status)
        order.status == "pending_payment" ? "awaiting_payment" : order.status
      else
        order.provisioning_state.presence || "queued"
      end
      {
        id: order.id, payment_status: order.status, state: state, ready: ready?(order),
        hostname: hostname(order), url: ready?(order) ? "https://#{hostname(order)}" : nil,
        allocated: node.present?, provisioned_at: order.provisioned_at&.iso8601,
        retryable: order.paid_at? && %w[paid fulfilled].include?(order.status) && !order.provisioned_at? && state == "failed"
      }
    end

    def self.resume!(order)
      raise PaidInstanceProvisioning::NotReady, "Only a paid installation can be resumed" unless order.paid_at? && %w[paid fulfilled].include?(order.status)
      order.with_lock do
        return order if order.provisioned_at?
        order.update!(provisioning_state: "queued", provisioning_error: nil)
        PaidInstanceProvisioningJob.perform_later(order.id)
      end
      order
    end
  end
end
