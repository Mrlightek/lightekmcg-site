# Read-only production probe. Prints booleans/counts and safe runtime identities,
# never credentials, checkout URLs, customer email addresses or bank details.
require 'json'
result = {revision: ENV['LIGHTEK_RELEASE'], rails_boot: true,
  stripe_configured: false, stripe_mode: nil, paid_stripe_orders: 0,
  provider_ready: false, native_acceptance_installations: [], federation_schema: false}
key = DymondBank::StripeCredentials.secret_key.to_s
result[:stripe_configured] = key.present?
result[:stripe_mode] = key.start_with?('sk_test_', 'rk_test_') ? 'test' : (key.present? ? 'live' : nil)
result[:paid_stripe_orders] = LightekCommerce::Order.where(payment_provider: 'stripe', status: %w[paid fulfilled]).where.not(paid_at: nil).count
provider = ComputeProvider.find_by(slug: 'linode')
result[:provider_ready] = provider&.credential_configured? && provider&.health_status == 'healthy'
result[:federation_schema] = ActiveRecord::Base.connection.table_exists?('lightek_reservation_peers')
result[:native_acceptance_installations] = GatekeeperInstallation.where(adapter: 'native_rails', component: 'lightek_app').filter_map do |installation|
  next unless installation.deployment_config.present?
  order = LightekCommerce::Order.find_by(provisioning_request_id: ProvisioningRequest.where(gatekeeper_node_id: installation.gatekeeper_node_id).select(:id))
  next unless order&.payment_provider.to_s.include?('acceptance')
  {installation_id: installation.id, order_id: order.id, adapter: installation.adapter}
end
puts 'LIGHTEK_RELEASE_PROBE=' + JSON.generate(result)
