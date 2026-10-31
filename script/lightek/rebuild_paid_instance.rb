# frozen_string_literal: true
# Run with: bundle exec rails runner script/lightek/rebuild_paid_instance.rb
# Recover the already-paid order in the authoritative production control plane.
# Active resources are reused. Only provider-confirmed deletions are reconciled.
raise "Run paid-order recovery in the production application runtime" unless Rails.env.production?
order_id = Integer(ENV.fetch("LIGHTEK_REBUILD_PAID_ORDER_ID", "1"))
order = LightekCommerce::Order.find(order_id)
raise "Order has not been paid" unless order.paid_at? && %w[paid fulfilled].include?(order.status)
request = ProvisioningRequest.find(order.provisioning_request_id)
raise "Paid order / request mismatch" unless request.owner.email_address == order.customer_email
raise "Only Linode recovery is supported" unless request.compute_provider&.slug == "linode"
operator = User.find_by!(role: "super_admin")
payment = order.attributes.slice("paid_at", "payment_reference", "total_cents", "currency")
request_id = request.id
subscription_id = request.subscription_id
# The job owns the advisory lock, provider inventory/reconciliation, DNS preflight
# and allocation. Never mutate node references outside that serialized path.
puts "Recovering paid-order installation #{order.id}; existing allocations will be reused"
LightekCommerce::PaidInstanceProvisioningJob.perform_now(order.id)
order.reload
raise "Paid order payment changed during recovery" unless order.attributes.slice(*payment.keys) == payment
raise "Paid order request changed during recovery" unless order.provisioning_request_id == request_id
raise "Paid subscription changed during recovery" unless request.reload.subscription_id == subscription_id
puts "PAID_PAYMENT_AND_SUBSCRIPTION_PRESERVED order=#{order.id}"
raise "Installation not ready: #{order.provisioning_error}" unless order.provisioning_state == "ready" && order.provisioned_at?
puts "PAID_INSTALLATION_READY order=#{order.id}"
