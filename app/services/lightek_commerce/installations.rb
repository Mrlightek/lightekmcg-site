# frozen_string_literal: true
module LightekCommerce
  module Installations
    def self.instance_orders
      Order.where.not(purpose: "subscription_renewal").or(Order.where(purpose: nil)).visible.joins(items: :product).where(lightek_commerce_products: {product_type: "lightek_instance"}).distinct
    end

    def self.scope_for(actor, operator: false)
      scope = instance_orders
      unless operator
        return scope.where(customer_email: actor.email_address).or(scope.where(hosting_owner_id: actor.id))
      end
      return scope if actor.role == "super_admin"
      return scope.where(site_id: LightekSettings::WebsiteIdentity.sites_for(actor).select(:id)) if actor.role == "admin"
      scope.none
    end

    def self.can_manage_access?(actor, order)
      return false unless actor&.persisted?
      return true if actor.role == "super_admin"
      if order.hosting_owner
        Gatekeeper::Hosting::Access.manages?(actor, order.hosting_owner)
      else
        actor.email_address == order.customer_email
      end
    end

    def self.ready?(order)
      order.paid_at? && %w[paid fulfilled].include?(order.status) && order.provisioning_state == "ready" && order.provisioned_at?
    end

    def self.hostname(order)
      return order.hosting_domain if order.hosting_domain.present?
      "client-#{order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}".downcase
    end

    def self.external_dns?(order)
      return false if order.hosting_domain.blank?

      platform_domain = ENV.fetch("LIGHTEK_AUTO_CLIENT_BASE_DOMAIN", "lightekmcg.com").downcase
      domain = hostname(order).downcase
      domain != platform_domain && !domain.end_with?(".#{platform_domain}")
    end

    def self.member_move_pending?(order)
      return false unless defined?(LightekPwa::Purchase) && defined?(LightekPwa::MemberBackend)
      purchase = LightekPwa::Purchase.find_by(order_id: order.id)
      return false unless purchase
      backend = LightekPwa::MemberBackend.find_by(site_id: purchase.site_id, user_id: purchase.user_id)
      backend && backend.status != 'dedicated_ready'
    end

    def self.summary(order)
      request = ProvisioningRequest.find_by(id: order.provisioning_request_id)
      node = request&.gatekeeper_node
      receipt = node&.metadata.to_h&.fetch('website_deployment_receipts', {})&.fetch(hostname(order), nil) ||
        node&.metadata.to_h&.fetch('website_deployment', {}) || {}
      state = if !order.paid_at? || !%w[paid fulfilled].include?(order.status)
        order.status == "pending_payment" ? "awaiting_payment" : order.status
      else
        order.provisioning_state.presence || "queued"
      end
      moving = ready?(order) && member_move_pending?(order)
      dns_record = if order.paid_at? && %w[paid fulfilled].include?(order.status) &&
          node&.ip_address.present? && !order.provisioned_at? && external_dns?(order)
        Gatekeeper::Hosting::Dns.external_record(domain: hostname(order), ip_address: node.ip_address)
      end
      {
        id: order.id, payment_status: order.status, state: moving ? "moving_content" : state, ready: ready?(order) && !moving,
        hostname: hostname(order), url: ready?(order) && !moving ? "https://#{hostname(order)}" : nil,
        allocated: node.present?, provisioned_at: order.provisioned_at&.iso8601,
        dns_record: dns_record,
        owner_onboarding_required_at_install: receipt.dig('health', 'owner_onboarding_required') == true,
        retryable: order.paid_at? && %w[paid fulfilled].include?(order.status) && !order.provisioned_at? && %w[failed awaiting_dns].include?(state)
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
