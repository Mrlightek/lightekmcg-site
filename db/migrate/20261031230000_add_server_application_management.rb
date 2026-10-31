class AddServerApplicationManagement < ActiveRecord::Migration[8.0]
  def change
    add_column :subscription_infrastructure_entitlements, :max_sites, :integer, null: false, default: 1
    create_table :gatekeeper_hosted_applications do |t|
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.references :gatekeeper_project, null: false, foreign_key: true
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.references :requested_by, null: false, foreign_key: {to_table: :users}
      t.references :gatekeeper_operation, foreign_key: true
      t.string :name, null: false
      t.string :domain, null: false
      t.string :public_key, null: false
      t.string :status, null: false, default: "queued"
      t.integer :remote_site_id
      t.text :error_message
      t.jsonb :receipt, null: false, default: {}
      t.datetime :started_at
      t.timestamps
    end
    add_index :gatekeeper_hosted_applications, :domain, unique: true
    add_index :gatekeeper_hosted_applications, :public_key, unique: true
    add_index :gatekeeper_hosted_applications, [:owner_id, :status]
  end
end
