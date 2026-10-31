# frozen_string_literal: true
# Operator-authorized internal acceptance order. No Stripe payment is simulated,
# charged, or recorded. The manual_acceptance provider keeps it distinguishable
# from real processor settlements. Retries reuse this exact order.
require "json"
raise "Production runtime required" unless Rails.env.production?
raise "Explicit manual-order authorization required" unless ENV["LIGHTEK_CREATE_MANUAL_PAID_ORDER"] == "1"
actor = User.where(role: "super_admin").order(:id).first!
reference = "manual_acceptance:paid-vps-20261031"
order = LightekCommerce::Order.find_by(payment_provider: "manual_acceptance", payment_reference: reference)
unless order
  product = LightekCommerce::Product.where(product_type: "lightek_instance", published: true)
    .where.not(subscription_plan_id: nil).order(:id).detect do |candidate|
      SubscriptionInfrastructureEntitlement.exists?(subscription_plan_id: candidate.subscription_plan_id)
    end
  unless product
    puts JSON.generate(instance_products: LightekCommerce::Product.where(product_type: "lightek_instance").pluck(:id, :subscription_plan_id, :published),
      infrastructure_entitlements: SubscriptionInfrastructureEntitlement.pluck(:id, :subscription_plan_id, :provisioning_profile_id, :compute_policy_id),
      subscription_plans: DymondBank::SubscriptionPlan.order(:id).limit(20).pluck(:id, :name),
      compute_policies: ComputePolicy.order(:id).pluck(:id, :slug, :active),
      provisioning_profiles: ProvisioningProfile.order(:id).pluck(:id, :slug, :active))
    raise "No configured instance product is available for the manual acceptance order"
  end
  product.with_lock do
    order = LightekCommerce::Order.find_by(site_id: product.site_id, payment_reference: reference)
    unless order
      order = LightekCommerce::OrderPlacement.call(site: product.site,
        customer_email: actor.email_address, quantities: {product.id.to_s => 1})
      order.update!(payment_provider: "manual_acceptance", payment_reference: reference,
        status: "paid", paid_at: Time.current)
    end
  end
end
raise "Existing manual acceptance order has a different owner" unless order.customer_email == actor.email_address
raise "Existing manual acceptance order is not paid" unless order.paid_at? && %w[paid fulfilled].include?(order.status)
File.write(Rails.root.join("tmp/manual_paid_instance_order_id"), order.id.to_s, mode: "w", perm: 0o600)
puts "MANUAL_ACCEPTANCE_ORDER_PAID order=#{order.id} stripe_charge_created=false"
# Enter the same locked provisioning job as a settled Commerce order.
LightekCommerce::PaidInstanceProvisioningJob.perform_now(order.id)
order.reload
raise "Installation is not ready" unless order.provisioning_state == "ready" && order.provisioned_at?
domain = "client-#{order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}"
notification = LightekCommerce::PaidInstanceProvisioning.publish_ready_notification!(order: order, customer: actor, domain: domain)
raise "Ready notification was not persisted" unless notification.persisted?
puts "READY_DASHBOARD_NOTIFICATION_PUBLISHED order=#{order.id} notification=#{notification.id}"
puts "MANUAL_ACCEPTANCE_INSTALLATION_READY order=#{order.id}"
