# frozen_string_literal: true
# Read-only paid instance acceptance audit. Run with:
#   RAILS_ENV=production bin/rails runner script/lightek/paid_instance_acceptance_audit.rb
require "json"

scope = LightekCommerce::Order.where(status: %w[paid fulfilled]).where.not(paid_at: nil).order(id: :desc)
order_id = ENV["LIGHTEK_ACCEPTANCE_ORDER_ID"].to_s
scope = scope.where(id: Integer(order_id)) unless order_id.empty?
orders = scope.limit(25).to_a.select do |order|
  order.items.any? { |item| item.product.product_type == "lightek_instance" }
end

results = orders.map do |order|
  request = ProvisioningRequest.find_by(id: order.provisioning_request_id) if order.provisioning_request_id.present?
  node = request&.gatekeeper_node
  receipt = node&.metadata.to_h&.fetch("website_deployment", {}) || {}
  {
    order_id: order.id,
    paid: order.paid_at.present?,
    order_status: order.status,
    provisioning_state: order.provisioning_state,
    provisioned: order.provisioned_at.present?,
    request_id: request&.id,
    request_status: request&.execution_status,
    node_id: node&.id,
    provider_resource_id: node&.provider_resource_id,
    hostname: receipt["url"],
    public_https_verified: receipt["public_https_verified"] == true,
    owner_login_verified: receipt["owner_login_verified"] == true,
    dashboard_verified: receipt.dig("health", "full_application_dashboard_verified") == true,
    mail_setup_status: receipt["mail_setup_status"],
    mail_registration_status: receipt["mail_registration_status"],
    acceptance_pass: order.provisioned_at.present? && node.present? &&
      receipt["public_https_verified"] == true &&
      receipt["owner_login_verified"] == true &&
      receipt.dig("health", "full_application_dashboard_verified") == true
  }
end

puts JSON.pretty_generate({
  audited_at: Time.current.iso8601,
  orders_examined: results.size,
  results: results
})
