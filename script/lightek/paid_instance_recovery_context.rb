# frozen_string_literal: true
# Read-only recovery diagnostics. Never prints credentials or customer details.
require "json"
raise "Production runtime required" unless Rails.env.production?
original = ActiveRecord::Base.connection_db_config.configuration_hash
result = {rails_env: Rails.env.to_s, rails_root: Rails.root.to_s,
  runtime_database: original[:database], databases: []}
begin
  databases = ActiveRecord::Base.connection.select_values("SELECT datname FROM pg_database WHERE NOT datistemplate").grep(/lightek/i)
  databases.each do |database|
    item = {database: database}
    begin
      ActiveRecord::Base.establish_connection(original.merge(database: database))
      connection = ActiveRecord::Base.connection
      if connection.select_value("SELECT to_regclass('public.lightek_commerce_orders')").present?
        item[:orders] = connection.select_all("SELECT id, status, paid_at IS NOT NULL AS paid FROM lightek_commerce_orders WHERE id = 1 OR paid_at IS NOT NULL ORDER BY id LIMIT 25").to_a
      else
        item[:orders_table_present] = false
      end
    rescue StandardError => error
      item[:error_class] = error.class.name
    end
    result[:databases] << item
  end
ensure
  ActiveRecord::Base.establish_connection(original)
end
result[:dns_zones] = Godaddy::DnsService.zones
result[:dns_vault_secret_present] = LightekVault::Secret.exists?(slug: ENV.fetch("GODADDY_VAULT_SLUG", "godaddy-dns"))
begin
  Gatekeeper::WebsiteDnsPublication.preflight!(hostname: "client-1.#{ENV.fetch('LIGHTEK_AUTO_CLIENT_BASE_DOMAIN', 'lightekmcg.com')}")
  result[:production_dns_preflight] = "passed"
rescue StandardError => error
  result[:production_dns_preflight] = error.class.name
end
begin
  actor = User.find_by!(role: "super_admin")
  provider = ComputeProvider.find_by!(slug: "linode")
  result[:linode_inventory] = provider.adapter(requested_by: actor.email_address).nodes.map { |node| node.slice("id", "status") }
  result[:registered_nodes] = GatekeeperNode.where(compute_provider: provider).pluck(:id, :provider_resource_id)
rescue StandardError => error
  result[:provider_error_class] = error.class.name
end
puts JSON.pretty_generate(result)
