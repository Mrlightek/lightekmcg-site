# frozen_string_literal: true
# Run with: bundle exec rails runner script/lightek/rebuild_paid_instance.rb
# Explicitly destructive recovery for the already-paid order. No new Stripe charge.
order_id = Integer(ENV.fetch("LIGHTEK_REBUILD_PAID_ORDER_ID", "1"))
order = LightekCommerce::Order.find(order_id)
raise "Order has not been paid" unless order.paid_at? && %w[paid fulfilled].include?(order.status)
raise "Completed installations cannot be rebuilt" if order.provisioned_at?
request = ProvisioningRequest.find(order.provisioning_request_id)
raise "Paid order / request mismatch" unless request.owner.email_address == order.customer_email
raise "Only Linode recovery is supported" unless request.compute_provider&.slug == "linode"
operator = User.find_by!(role: "super_admin")
adapter = request.compute_provider.adapter(requested_by: operator.email_address)
node = request.gatekeeper_node
if node
  provider_id = node.provider_resource_id.to_s
  raise "Missing provider resource ID" if provider_id.empty?
  begin
    current = adapter.node(provider_id)
    raise "Provider ID mismatch" unless current.fetch("id").to_s == provider_id
    puts "Destroying failed Linode #{provider_id} for existing paid order #{order.id}"
    adapter.destroy_node(provider_id)
  rescue StandardError => e
    raise unless e.message.start_with?("Provider HTTP 404:")
    puts "Linode #{provider_id} already deleted"
  end
  # Wait until deletion is confirmed before allowing another billable allocation.
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
  loop do
    begin
      adapter.node(provider_id)
    rescue StandardError => e
      raise unless e.message.start_with?("Provider HTTP 404:")
      break
    end
    raise "Deletion not confirmed; refusing new allocation" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 5
  end
  Gatekeeper::Compute::DeletedNodeReconciliation.call!(request: request, requested_by: operator.email_address)
end
puts "Starting clean paid-order installation #{order.id}"
LightekCommerce::PaidInstanceProvisioningJob.perform_now(order.id)
order.reload
raise "Installation not ready: #{order.provisioning_error}" unless order.provisioning_state == "ready" && order.provisioned_at?
puts "PAID_INSTALLATION_READY order=#{order.id}"
