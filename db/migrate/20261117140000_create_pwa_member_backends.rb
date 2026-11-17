class CreatePwaMemberBackends < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_shared_pools do |t|
      t.references :site, null: false
      t.references :operator, null: false, foreign_key: {to_table: :users}
      t.references :launch, foreign_key: {to_table: :gatekeeper_application_launches}
      t.references :node, foreign_key: {to_table: :gatekeeper_nodes}
      t.string :request_key, null: false, index: {unique: true}
      t.string :name, null: false
      t.string :status, null: false, default: 'provisioning'
      t.integer :max_members, null: false, default: 4
      t.bigint :member_storage_bytes, null: false, default: 536870912
      t.integer :monthly_cost_ceiling_cents, null: false
      t.timestamps
    end
    create_table :lightek_pwa_member_backends do |t|
      t.references :site, null: false
      t.references :user, null: false, foreign_key: true
      t.references :shared_pool, foreign_key: {to_table: :lightek_pwa_shared_pools}
      t.references :launch, foreign_key: {to_table: :gatekeeper_application_launches}
      t.references :order, foreign_key: {to_table: :lightek_commerce_orders}
      t.string :public_key, null: false, index: {unique: true}
      t.string :hostname, null: false, index: {unique: true}
      t.string :status, null: false, default: 'queued'
      t.string :error_code
      t.jsonb :migration_receipt, null: false, default: {}
      t.bigint :copied_bytes, null: false, default: 0
      t.datetime :retire_after
      t.timestamps
    end
    add_index :lightek_pwa_member_backends, [:site_id, :user_id], unique: true, name: 'pwa_member_backend_identity'
    change_column_null :lightek_reservation_peers, :order_id, true
    add_reference :lightek_reservation_peers, :member_backend, foreign_key: {to_table: :lightek_pwa_member_backends}, index: {unique: true}
    create_table :lightek_pwa_member_signup_requests do |t|
      t.references :site, null: false
      t.references :user, null: false, foreign_key: true
      t.string :state, null: false, default: 'queued'
      t.timestamps
    end
    add_index :lightek_pwa_member_signup_requests, [:site_id, :user_id], unique: true, name: 'pwa_signup_backend_request'
    create_table :lightek_pwa_member_tickets do |t|
      t.references :member_backend, null: false, foreign_key: {to_table: :lightek_pwa_member_backends}
      t.string :token_digest, null: false, index: {unique: true}
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at
      t.timestamps
    end
  end
end
