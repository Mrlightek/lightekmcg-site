class AddProviderToManagedDnsEnrollments < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_managed_dns_enrollments, :provider_kind, :string, default: "cloudflare", null: false
    add_check_constraint :lightek_managed_dns_enrollments, "provider_kind IN ('cloudflare', 'powerdns')",
      name: "managed_dns_provider_kind"
  end
end
