# frozen_string_literal: true
require "securerandom"

module LightekCommerce
  # Payment already settled by signed Stripe webhook before this service runs.
  # This service binds each order to one durable Gatekeeper provisioning request.
  class PaidInstanceProvisioning
    class NotReady < StandardError; end

    def self.call!(order:)
      product_items = order.items.select { |item| item.product.product_type == "lightek_instance" }
      return if product_items.empty?
      raise NotReady, "One installation per checkout" unless product_items.size == 1 && product_items.first.quantity == 1
      item = product_items.first
      product = item.product
      raise NotReady, "Instance product has no configured subscription plan" unless product.subscription_plan_id.present?
      actor = User.find_by(role: "super_admin") || raise(NotReady, "No Lightek super admin operator configured")
      raise NotReady, "Paid order required" unless order.paid_at? && %w[paid fulfilled].include?(order.status)

      customer = User.find_by(email_address: order.customer_email)
      unless customer
        customer = User.create!(email_address: order.customer_email,
          first_name: order.customer_email.split("@").first.to_s.first(40),
          last_name: "Customer", role: "client",
          password: SecureRandom.urlsafe_base64(36), password_confirmation: nil)
      end

      request = nil
      order.with_lock do
        return order if order.provisioned_at?
        request = ProvisioningRequest.find_by(id: order.provisioning_request_id) if order.provisioning_request_id.present?
        unless request
          plan = DymondBank::SubscriptionPlan.find(product.subscription_plan_id)
          subscription = DymondBank::Subscription.create!(
            subscriber: customer, plan: plan,
            status: "active", billing_interval: "monthly",
            current_period_start: Time.current, current_period_end: 1.month.from_now)
          request = Gatekeeper::Compute::ProvisioningRequestBuilder.call(
            subscription: subscription, requested_by: actor.email_address,
            estimated_monthly_cost_cents: Integer(ENV.fetch("LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS")))
          order.update!(provisioning_request_id: request.id, provisioning_state: "requested")
        end
      end
      raise NotReady, "Provisioning ownership mismatch" unless request.owner == customer
      raise NotReady, "Provisioning subscription differs from the purchased plan" unless
        request.subscription&.subscriber == customer &&
        request.subscription.plan_id == product.subscription_plan_id
      raise NotReady, "Cloud provider configuration missing" unless request.compute_provider

      if request.gatekeeper_node.nil?
        unless request.executable?
          raise NotReady, "Only failed or awaiting-approval requests can be reauthorized" unless
            %w[failed awaiting_approval awaiting_cost awaiting_provider draft ready].include?(request.execution_status)
          request.update!(
            selected_region: ENV.fetch("LIGHTEK_AUTO_VPS_REGION"),
            selected_plan: ENV.fetch("LIGHTEK_AUTO_VPS_PLAN"),
            selected_image: ENV.fetch("LIGHTEK_AUTO_VPS_IMAGE"),
            node_label: "lightek-client-#{order.id}",
            execution_status: "awaiting_approval")
          Gatekeeper::Compute::ApprovalService.call(request: request, requested_by: actor.email_address)
        end
        raise NotReady, "Compute policy has not auto-approved paid instance" unless request.executable?
      end

      domain = "client-#{order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}"
      slug = "commerce-client-website-#{order.id}"
      # Secrets are managed through Lightek Vault. No generated plaintext password is
      # saved to the order or to GitHub, and separate onboarding is required to sign in.
      unless request.metadata.to_h.fetch("website_deployments", {}).key?(domain)
        LightekVault::Service.store!(
          name: "Commerce client installation #{order.id}", slug: slug,
          payload: {"owner_password" => SecureRandom.urlsafe_base64(36)},
          provider: "lightek", purpose: "website_deploy",
          access_policy: {"consumers" => [Gatekeeper::WebsiteDeployment::CONSUMER],
                          "purposes" => ["website_deploy"]},
          requested_by: actor.email_address)
      end

      config = Gatekeeper::WebsiteDeployment.configuration(owner: customer, domain: domain,
        site_name: "#{customer.first_name}'s Lightek", headline: "Welcome to Lightek",
        description: "Your Lightek workspace", certificate_email: actor.email_address,
        credential_slug: slug)
      unless request.metadata.to_h.fetch("website_deployments", {}).key?(domain)
        Gatekeeper::WebsiteDeployment.register!(actor: actor, record: request, config: config)
      end

      order.update!(provisioning_state: "deploying", provisioning_error: nil)
      Gatekeeper::WebsiteDeployment.provision_and_run!(actor: actor, request: request, domain: domain)
      # The packager acceptance receipt has passed before the order is marked ready.
      order.update!(provisioning_state: "ready", provisioned_at: Time.current)
      begin
        InstanceReadyMailer.ready(order.id).deliver_later
      rescue StandardError => e
        Rails.logger.error("[Commerce] installation ready but invitation enqueue failed order=#{order.id} #{e.class}")
      end
      order
    rescue StandardError => e
      if order&.persisted? && !order.reload.provisioned_at?
        order.update_columns(provisioning_state: "failed",
          provisioning_error: "#{e.class}: #{e.message}".slice(0, 1000))
      end
      raise
    end
  end
end
