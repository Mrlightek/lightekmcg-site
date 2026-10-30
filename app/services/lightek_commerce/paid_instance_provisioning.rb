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

      vps = required_vps_configuration!

      customer = User.find_by(email_address: order.customer_email)
      unless customer
        begin
          customer = User.create!(email_address: order.customer_email,
            first_name: order.customer_email.split("@").first.to_s.first(40),
            last_name: "Customer", role: "client",
            password: SecureRandom.urlsafe_base64(36))
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          customer = User.find_by!(email_address: order.customer_email)
        end
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
            estimated_monthly_cost_cents: vps.fetch(:monthly_cost_cents))
          order.update!(provisioning_request_id: request.id, provisioning_state: "requested")
        end
      end
      raise NotReady, "Provisioning ownership mismatch" unless request.owner == customer
      raise NotReady, "Provisioning subscription differs from the purchased plan" unless
        request.subscription&.subscriber == customer &&
        request.subscription.plan_id == product.subscription_plan_id
      raise NotReady, "Cloud provider configuration missing" unless request.compute_provider

      # Reconcile a provider-confirmed external deletion before deciding whether
      # the original paid request needs a replacement allocation.
      Gatekeeper::Compute::DeletedNodeReconciliation.call!(
        request: request, requested_by: actor.email_address
      ) if request.gatekeeper_node.present?

      if request.gatekeeper_node.nil?
        unless request.executable?
          raise NotReady, "Only failed or awaiting-approval requests can be reauthorized" unless
            %w[failed awaiting_approval awaiting_cost awaiting_provider draft ready].include?(request.execution_status)
          request.update!(
            selected_region: vps.fetch(:region),
            selected_plan: vps.fetch(:plan),
            selected_image: vps.fetch(:image),
            node_label: "lightek-client-#{order.id}-r#{Array(request.metadata.to_h["retired_provider_nodes"]).size + 1}",
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
      # Record post-activation work separately; never reset the paid installation.
      # Pending mail work is independent of customer activation and can be retried.
      begin
        receipt = request.reload.gatekeeper_node&.metadata.to_h.fetch("website_deployment", {})
        if receipt["mail_setup_status"] == "pending" || receipt["mail_registration_status"] == "pending"
          LightekCommerce::PendingMailRecoveryJob.perform_later(request.id)
        end
      rescue StandardError => e
        Rails.logger.error("[Commerce] mail recovery enqueue failed order=#{order.id} #{e.class}: #{e.message}")
      end
      # Cloud providers may restrict SMTP on newly provisioned accounts.
      # File an idempotent provider support request, but never make the
      # customer's paid application activation contingent on port approval.
      begin
        node = request.reload.gatekeeper_node
        metadata = request.metadata.to_h
        unless metadata["mail_port_ticket_id"].present?
          ticket = request.compute_provider.adapter(requested_by: actor.email_address).create_support_ticket(
            summary: "Enable mail ports on Lightek customer instance #{node.provider_resource_id}",
            description: "Please review and remove inbound/outbound SMTP mail port restrictions for Linode #{node.provider_resource_id} (#{node.ip_address}). Lightek Mail requires TCP 25 inbound and outbound, TCP 465/587 authenticated submission, and TCP 993 IMAPS for customer access. Mail server authorization, abuse limits, SPF, DKIM, DMARC and TLS are configured separately. Please confirm when restrictions are lifted.",
            linode_id: node.provider_resource_id
          )
          raise "Mail port support ticket response missing ID" if ticket["id"].blank?
          request.update!(metadata: request.metadata.to_h.merge("mail_port_ticket_attempted" => true, "mail_port_ticket_id" => ticket["id"], "mail_port_ticket_status" => "submitted"))
        end
      rescue StandardError => e
        Rails.logger.error("[Commerce] Linode mail-port support request failed order=#{order.id} #{e.class}: #{e.message}")
      end
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

    def self.required_vps_configuration!
      names = %w[
        LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS
        LIGHTEK_AUTO_VPS_REGION
        LIGHTEK_AUTO_VPS_PLAN
        LIGHTEK_AUTO_VPS_IMAGE
      ]
      missing = names.select { |name| ENV[name].to_s.strip.empty? }
      raise NotReady, "Missing paid VPS configuration: #{missing.join(', ')}" if missing.any?

      cents = Integer(ENV.fetch("LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS"), 10)
      raise NotReady, "LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS must be positive" unless cents.positive?

      {
        monthly_cost_cents: cents,
        region: ENV.fetch("LIGHTEK_AUTO_VPS_REGION").strip,
        plan: ENV.fetch("LIGHTEK_AUTO_VPS_PLAN").strip,
        image: ENV.fetch("LIGHTEK_AUTO_VPS_IMAGE").strip
      }
    rescue ArgumentError
      raise NotReady, "LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS must be a positive integer"
    end
  end
end
