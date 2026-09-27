class CreateProvisioningRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :provisioning_requests do |t|
      t.string :owner_type
      t.bigint :owner_id

      t.references :subscription,
                   foreign_key: { to_table: :dymond_bank_subscriptions }

      t.references :subscription_plan,
                   foreign_key: { to_table: :dymond_bank_subscription_plans }

      t.references :subscription_infrastructure_entitlement,
                   foreign_key: true

      t.references :provisioning_profile, foreign_key: true
      t.references :compute_policy, foreign_key: true
      t.references :compute_provider, foreign_key: true
      t.references :gatekeeper_operation, foreign_key: true

      t.integer :requested_node_count, null: false, default: 1
      t.integer :estimated_monthly_cost_cents

      t.string :approval_status, null: false, default: "pending"
      t.string :execution_status, null: false, default: "draft"

      t.text :approval_reason
      t.string :approved_by
      t.datetime :approved_at

      t.string :error_class
      t.text :error_message

      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :provisioning_requests, [:owner_type, :owner_id]
    add_index :provisioning_requests, :approval_status
    add_index :provisioning_requests, :execution_status
    add_index :provisioning_requests, :created_at
  end
end
