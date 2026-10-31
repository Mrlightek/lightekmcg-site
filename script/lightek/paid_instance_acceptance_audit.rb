# frozen_string_literal: true
# Production acceptance: provider inventory, DNS, HTTPS, real owner login and
# full dashboard probes. Receipt/database flags alone never pass this audit.
require "json"
require "open3"
require "resolv"
raise "Run acceptance in the production application runtime" unless Rails.env.production?

scope = LightekCommerce::Order.where(status: %w[paid fulfilled]).where.not(paid_at: nil).order(id: :desc)
order_id = ENV["LIGHTEK_ACCEPTANCE_ORDER_ID"].to_s
scope = scope.where(id: Integer(order_id)) unless order_id.empty?
orders = scope.limit(25).to_a.select do |order|
  order.items.any? { |item| item.product.product_type == "lightek_instance" }
end
operator = User.find_by!(role: "super_admin")
results = orders.map do |order|
  request = ProvisioningRequest.find_by(id: order.provisioning_request_id)
  node = request&.gatekeeper_node
  receipt = node&.metadata.to_h&.fetch("website_deployment", {}) || {}
  result = {
    order_id: order.id, paid: order.paid_at.present?, order_status: order.status,
    provisioning_state: order.provisioning_state, provisioned: order.provisioned_at.present?,
    provisioned_at: order.provisioned_at&.iso8601,
    request_id: request&.id, request_status: request&.execution_status,
    node_id: node&.id, provider_resource_id: node&.provider_resource_id,
    hostname: receipt["url"], public_https_verified: false,
    owner_login_verified: false, dashboard_verified: false, dns_verified: false,
    provider_running: false, installation_receipt_verified: false,
    mail_setup_status: receipt["mail_setup_status"],
    mail_registration_status: receipt["mail_registration_status"], acceptance_pass: false
  }
  secret = nil
  begin
    raise "Missing request or registered node" unless request && node && request.compute_provider_id == node.compute_provider_id
    raise "Invalid paid request ownership" unless request.owner == node.owner &&
      request.owner.email_address == order.customer_email && request.subscription&.subscriber == request.owner
    provider = request.compute_provider.adapter(requested_by: operator.email_address).node(node.provider_resource_id)
    result[:provider_running] = provider.fetch("id").to_s == node.provider_resource_id.to_s && provider["status"] == "running"
    ipv4 = Array(provider["ipv4"]).first
    raise "Provider resource is not running at its registered IP" unless result[:provider_running] && ipv4 == node.ip_address
    domain = "client-#{order.id}.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}".downcase
    result[:hostname] = domain
    result[:public_ip] = ipv4
    result[:dns_verified] = Resolv.getaddresses(domain).uniq.sort == [ipv4]
    raise "Public DNS does not match the provider IP" unless result[:dns_verified]
    config = Gatekeeper::WebsiteDeployment.preview(actor: operator, record: node, domain: domain)
    raise "Receipt belongs to a different installation" unless receipt["url"] == "https://#{domain}" && receipt["release"].present?
    secret = LightekVault::Service.checkout!(slug: config.fetch("credential_slug"),
      consumer: Gatekeeper::WebsiteDeployment::CONSUMER, purpose: "website_deploy",
      requested_by: operator.email_address)
    # Secret goes on stdin only; neither stdout/stderr nor argv contains it.
    stdout, _stderr, status = Open3.capture3("python3", Rails.root.join("script/lightek/verify_paid_instance.py").to_s,
      stdin_data: JSON.generate(domain: domain, release: receipt.fetch("release"),
        owner_email: config.fetch("owner_email"), owner_password: secret.fetch("owner_password")))
    raise "Live HTTPS, login or dashboard verification failed" unless status.success?
    health = JSON.parse(stdout)
    result[:public_https_verified] = true
    result[:owner_login_verified] = true
    result[:dashboard_verified] = health["full_application_dashboard_verified"] == true
    result[:installation_receipt_verified] = receipt["public_https_verified"] == true &&
      receipt["owner_login_verified"] == true && receipt.dig("health", "full_application_dashboard_verified") == true
    result[:acceptance_pass] = result[:paid] && result[:provider_running] && result[:dns_verified] &&
      result[:public_https_verified] && result[:owner_login_verified] && result[:dashboard_verified] &&
      result[:installation_receipt_verified] && order.provisioning_state == "ready" && order.provisioned_at.present?
  rescue StandardError => error
    result[:error_class] = error.class.name
    # Avoid emitting HTTP/Vault exception messages that could contain secrets.
  ensure
    secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  end
  result
end
pass = results.any? && results.all? { |result| result[:acceptance_pass] }
puts JSON.pretty_generate(audited_at: Time.current.iso8601, orders_examined: results.size,
  acceptance_pass: pass, results: results)
exit(pass ? 0 : 1)
