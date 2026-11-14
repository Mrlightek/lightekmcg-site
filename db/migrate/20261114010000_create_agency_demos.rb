class CreateAgencyDemos < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_agency_demo_settings do |t|
      t.references :agency, null: false, foreign_key: {to_table: :users}, index: {unique: true}
      t.bigint :public_site_id
      t.bigint :upgrade_product_id
      t.boolean :public_enabled, null: false, default: false
      t.integer :duration_days, null: false, default: 14
      t.integer :max_active, null: false, default: 20
      t.timestamps
    end
    create_table :lightek_agency_demo_requests do |t|
      t.references :agency, null: false, foreign_key: {to_table: :users}
      t.string :email_address, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :nonce, null: false
      t.string :status, null: false, default: 'pending'
      t.datetime :invitation_queued_at
      t.datetime :verified_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :lightek_agency_demo_requests, [:agency_id, :email_address, :created_at], name: :index_demo_requests_on_agency_email_created
    create_table :lightek_agency_demos do |t|
      t.references :agency, null: false, foreign_key: {to_table: :users}
      t.references :client, foreign_key: {to_table: :users, on_delete: :nullify}
      t.bigint :site_id
      t.bigint :demo_request_id
      t.bigint :upgrade_order_id
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :status, null: false, default: 'active'
      t.boolean :created_client, null: false, default: false
      t.datetime :expires_at, null: false
      t.datetime :converted_at
      t.datetime :cleaned_at
      t.string :cleanup_error
      t.timestamps
    end
    add_index :lightek_agency_demos, :public_id, unique: true
    add_index :lightek_agency_demos, :site_id, unique: true, where: 'site_id IS NOT NULL'
    add_index :lightek_agency_demos, :demo_request_id, unique: true, where: 'demo_request_id IS NOT NULL'
    add_index :lightek_agency_demos, [:status, :expires_at]
    add_column :lightek_commerce_orders, :agency_demo_id, :bigint
    add_column :lightek_commerce_orders, :demo_content, :jsonb, null: false, default: {}
    add_index :lightek_commerce_orders, :agency_demo_id
  end
end
