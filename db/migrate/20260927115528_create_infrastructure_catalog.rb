class CreateInfrastructureCatalog < ActiveRecord::Migration[8.0]
  def change
    create_table :provisioning_profiles do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :purpose, null: false
      t.string :os_image, null: false, default: "ubuntu-24.04"
      t.integer :cpu_cores
      t.integer :memory_mb
      t.integer :disk_gb
      t.boolean :backups_enabled, null: false, default: true
      t.boolean :monitoring_enabled, null: false, default: true
      t.jsonb :services, null: false, default: []
      t.jsonb :firewall_rules, null: false, default: []
      t.jsonb :configuration, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :provisioning_profiles, :slug, unique: true

    create_table :compute_policies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :purpose, null: false
      t.references :preferred_provider, foreign_key: { to_table: :compute_providers }
      t.references :fallback_provider, foreign_key: { to_table: :compute_providers }
      t.integer :monthly_cost_ceiling_cents
      t.integer :automatic_approval_ceiling_cents
      t.jsonb :allowed_regions, null: false, default: []
      t.jsonb :required_capabilities, null: false, default: []
      t.jsonb :rules, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :compute_policies, :slug, unique: true

    create_table :subscription_infrastructure_entitlements do |t|
      t.references :subscription_plan, null: false, foreign_key: { to_table: :dymond_bank_subscription_plans }
      t.references :provisioning_profile, foreign_key: true
      t.references :compute_policy, foreign_key: true
      t.integer :node_quantity, null: false, default: 0
      t.boolean :auto_provision, null: false, default: false
      t.jsonb :feature_entitlements, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :subscription_infrastructure_entitlements, :subscription_plan_id, unique: true, name: "idx_subscription_infra_entitlements_plan"

    change_table :gatekeeper_nodes, bulk: true do |t|
      t.references :compute_provider, foreign_key: true
      t.references :provisioning_profile, foreign_key: true
      t.references :compute_policy, foreign_key: true
      t.string :provider_resource_id
      t.string :owner_type
      t.bigint :owner_id
      t.string :purpose
      t.string :plan
      t.string :image
      t.string :public_ipv6
      t.string :private_ip
      t.integer :estimated_monthly_cost_cents
    end
    add_index :gatekeeper_nodes, [:owner_type, :owner_id]
    add_index :gatekeeper_nodes, :provider_resource_id
  end
end
