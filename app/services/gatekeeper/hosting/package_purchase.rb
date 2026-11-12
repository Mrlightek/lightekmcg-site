module Gatekeeper
  module Hosting
    class PackagePurchase
      def self.validate!(snapshot:, retail_cents:, actor:)
        provider = ComputeProvider.active.find(snapshot.fetch("compute_provider_id"))
        raise Access::Denied, "Hosting is temporarily unavailable" unless provider.slug == "linode" && provider.health_status == "healthy"
        catalog = Compute::LinodeCatalogService.call(provider: provider, requested_by: actor.email_address, region: snapshot.fetch("region"))
        plan = catalog.fetch("plans").find { |item| item["id"] == snapshot.fetch("plan") }
        cost = plan&.fetch("monthly_cents", nil).to_i
        raise Access::Denied, "Hosting package needs an updated price. Contact support." unless cost.positive? &&
          cost <= snapshot.fetch("monthly_cost_ceiling_cents").to_i && retail_cents >= cost + snapshot.fetch("minimum_margin_cents").to_i
        raise Access::Denied, "Hosting region is unavailable" unless catalog.fetch("regions").any? { |region| region["id"] == snapshot.fetch("region") }
        GatekeeperApplicationTemplate.available.find(snapshot.fetch("template_id"))
        DymondBank::SubscriptionPlan.find(snapshot.fetch("subscription_plan_id"))
        entitlement = SubscriptionInfrastructureEntitlement.find_by(subscription_plan_id: snapshot.fetch("subscription_plan_id"))
        raise Access::Denied, "Hosting plan needs a website allowance" unless entitlement && entitlement.max_sites.positive?
        raise Access::Denied, "Ubuntu 24.04 is unavailable" unless catalog.fetch("images").any? { |image| image["id"] == "linode/ubuntu24.04" }
        snapshot
      rescue Access::Denied
        raise
      rescue StandardError => error
        Rails.logger.warn("[Hosting package] preflight failed: #{error.class}")
        raise Access::Denied, "Hosting is temporarily unavailable. Contact support."
      end

      def self.provision!(order:)
        raise Access::Denied, "Payment confirmation required" unless order.paid_at? && %w[paid fulfilled].include?(order.status)
        recurring = order.commerce_subscription || raise(Access::Denied, "Paid hosting subscription is missing")
        Stripe.api_key = DymondBank::StripeCredentials.secret_key
        data = Stripe::Subscription.retrieve(recurring.processor_reference).to_h.deep_stringify_keys
        recurring.with_lock { LightekCommerce::SubscriptionEvents.apply!(subscription: recurring, data: data) }
        raise Access::Denied, "Hosting requires an active, paid subscription" unless recurring.status == "active" && recurring.current_period_end > Time.current
        operator = User.find_by!(role: "super_admin")
        buyer = User.find_by!(email_address: order.customer_email)
        owner = order.hosting_owner || buyer
        raise Access::Denied, "The agency no longer manages this client" unless Access.manages?(buyer, owner)
        snapshot = order.items.sole.purchase_snapshot.fetch("hosting")
        launch = order.gatekeeper_application_launch
        unless launch
          validate!(snapshot: snapshot, retail_cents: order.items.sole.unit_price_cents, actor: operator)
          order.with_lock do
            launch = order.gatekeeper_application_launch
            unless launch
              launch = Launches.create!(actor: operator, enqueue: false, attributes: snapshot.merge(
                "owner_id" => owner.id, "name" => order.items.sole.name, "domain" => LightekCommerce::Installations.hostname(order)))
              order.update!(gatekeeper_application_launch: launch, provisioning_request_id: launch.provisioning_request_id,
                provisioning_state: "deploying", provisioning_error: nil)
            end
          end
        end
        unless launch.template_snapshot["reservation_federation"]
          connection = LightekReservations::Federation::Issuer.ensure!(order: order, merchant: owner, domain: launch.domain)
          launch.update!(template_snapshot: launch.template_snapshot.merge("reservation_federation" => connection))
        end
        launch.update!(status: "queued") if launch.status == "failed"
        Launches.perform!(launch)
        raise Access::Denied, "Hosting installation has not passed verification" unless launch.reload.status == "ready"
        recurring = order.commerce_subscription || raise(Access::Denied, "Paid hosting subscription is missing")
        recurring.with_lock do
          unless recurring.bank_subscription
            bank = DymondBank::Subscription.create!(subscriber: owner,
              plan_id: snapshot.fetch("subscription_plan_id"), status: recurring.status,
              billing_interval: "monthly", current_period_start: order.paid_at,
              current_period_end: recurring.current_period_end || raise(Access::Denied, "Subscription billing period is missing"))
            recurring.update!(bank_subscription: bank)
          end
        end
        order.update!(provisioning_state: "ready", provisioned_at: Time.current, provisioning_error: nil)
        LightekCommerce::PaidInstanceProvisioning.publish_ready_notification!(order: order, customer: owner, domain: launch.domain)
        order
      end
    end
  end
end
