class CreatePlatformShipping < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_shipping_accounts do |t|
      t.string :provider, default: "fedex", null: false, index: {unique: true}
      t.string :credential_slug, null: false
      t.boolean :sandbox, default: true, null: false
      t.boolean :enabled, default: false, null: false
      t.boolean :production_approved, default: false, null: false
      t.integer :markup_bps, default: 0, null: false
      t.integer :fixed_markup_cents, default: 0, null: false
      t.integer :minimum_margin_cents, default: 100, null: false
      t.timestamps
    end
    create_table :lightek_shipping_profiles do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}, index: {unique: true}
      t.jsonb :origin, default: {}, null: false
      t.jsonb :default_package, default: {}, null: false
      t.integer :customer_markup_bps, default: 0, null: false
      t.timestamps
    end
    add_column :lightek_commerce_products, :shipping_weight_lb, :decimal, precision: 10, scale: 3
    add_column :lightek_commerce_products, :shipping_length_in, :integer
    add_column :lightek_commerce_products, :shipping_width_in, :integer
    add_column :lightek_commerce_products, :shipping_height_in, :integer
    create_table :lightek_shipping_quotes do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :public_key, null: false, index: {unique: true}
      t.string :broker_reference, index: true
      t.string :service_code, null: false
      t.string :service_name, null: false
      t.string :currency, default: "usd", null: false
      t.integer :carrier_cost_cents
      t.integer :platform_price_cents, null: false
      t.integer :customer_price_cents, null: false
      t.boolean :sandbox, default: true, null: false
      t.jsonb :shipment_payload, default: {}, null: false
      t.string :cart_fingerprint
      t.datetime :expires_at, null: false
      t.references :purchase_order, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.timestamps
    end
    add_reference :lightek_commerce_orders, :shipping_quote, foreign_key: {to_table: :lightek_shipping_quotes}
    add_index :lightek_commerce_orders, :shipping_quote_id, unique: true, where: "shipping_quote_id IS NOT NULL AND (purpose IS NULL OR purpose <> 'shipping_label')", name: "idx_shipping_quote_checkout"
    create_table :lightek_shipping_shipments do |t|
      t.references :quote, null: false, foreign_key: {to_table: :lightek_shipping_quotes}, index: {unique: true}
      t.string :public_key, null: false, index: {unique: true}
      t.string :status, default: "queued", null: false
      t.string :tracking_number
      t.string :carrier_status
      t.datetime :submitted_at
      t.datetime :completed_at
      t.integer :actual_carrier_cost_cents
      t.string :error_message
      t.timestamps
    end
    add_check_constraint :lightek_shipping_quotes, "platform_price_cents > 0 AND customer_price_cents >= platform_price_cents AND (carrier_cost_cents IS NULL OR platform_price_cents > carrier_cost_cents)", name: "shipping_retail_price_valid"
  end
end
