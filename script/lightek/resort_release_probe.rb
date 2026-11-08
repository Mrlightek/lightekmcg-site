# Read-only production probe. Prints booleans/counts and safe runtime identities,
# never credentials, checkout URLs, customer email addresses or bank details.
require 'json'
result = {revision: ENV['LIGHTEK_RELEASE'], rails_boot: true,
  stripe_configured: false, stripe_mode: nil, paid_stripe_orders: 0,
  provider_ready: false, native_acceptance_installations: [], federation_schema: false, client_installations: []}
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
result[:client_installations] = GatekeeperInstallation.where(component: 'lightek_app').map { |installation| {id: installation.id, adapter: installation.adapter, native_profile: installation.deployment_config.present?, account_id: installation.account_id} }
puts 'LIGHTEK_RELEASE_PROBE=' + JSON.generate(result)

# Inspect the actual installation marker and running dependency services on
# recorded client nodes; never infer a running Rails container from an old file.
require 'net/ssh'
require 'shellwords'
inspections = []
GatekeeperNode.where.not(status: %w[decommissioned deleting delete_failed]).find_each do |node|
  next if node.local? || node.metadata.to_h['role'] == 'production'
  domains = node.metadata.to_h.fetch('website_deployments', {}).keys.select { |host| host.match?(/\Aclient-\d+\./) }
  next if domains.empty?
  secret = nil
  begin
    options = {port: node.ssh_port, non_interactive: true, verify_host_key: :accept_new, timeout: 10}
    if node.ssh_key_path.present?
      options[:keys] = [node.ssh_key_path]
    else
      secret = LightekVault::Service.checkout!(slug: node.metadata.fetch('node_credential_secret_slug'),
        consumer: Gatekeeper::WebsiteDeployment::CONSUMER, purpose: 'node_bootstrap', requested_by: 'resort-release-inventory')
      options[:password] = secret.fetch('root_password')
    end
    code = <<~'PYTHON'
      import json,pathlib,subprocess
      values=[]
      for root in pathlib.Path('/opt/lightek-sites').glob('*'):
        marker=root/'managed.json'
        if not marker.is_file(): continue
        data=json.loads(marker.read_text())
        values.append({'adapter':data.get('adapter','legacy_container'),'native_current':(root/'current').exists()})
      result=subprocess.run(['docker','ps','--format','{{.Label "com.docker.compose.service"}}'],capture_output=True,text=True,timeout=10)
      print(json.dumps({'installations':values,'running_compose_services':result.stdout.splitlines()}))
    PYTHON
    output = Net::SSH.start(node.ip_address, node.ssh_user, **options) { |ssh| Timeout.timeout(20) { ssh.exec!("python3 -c #{Shellwords.escape(code)}") } }
    inspections << {node_id: node.id, runtime: JSON.parse(output.to_s)}
  rescue StandardError => error
    inspections << {node_id: node.id, inspection_error: error.class.name}
  ensure
    secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  end
  break if inspections.size >= 10
end
puts 'LIGHTEK_CLIENT_RUNTIME_INVENTORY=' + JSON.generate(inspections)
