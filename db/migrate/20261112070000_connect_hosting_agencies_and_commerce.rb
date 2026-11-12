class ConnectHostingAgenciesAndCommerce < ActiveRecord::Migration[8.0]
  def change
    add_column :gatekeeper_application_templates, :lightek_application, :boolean, default: false, null: false
    add_reference :users, :agency, foreign_key: {to_table: :users}
    create_table :agency_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.string :brand_name, null: false
      t.string :logo_url
      t.string :support_email
      t.string :accent_color, default: "#d4af37", null: false
      t.timestamps
    end
    add_column :lightek_commerce_products, :billing_interval, :string, default: "one_time", null: false
    add_column :lightek_commerce_products, :track_inventory, :boolean, default: true, null: false
    add_column :lightek_commerce_order_items, :purchase_snapshot, :jsonb, default: {}, null: false
    add_column :lightek_commerce_orders, :hosting_domain, :string
    add_reference :lightek_commerce_orders, :hosting_owner, foreign_key: {to_table: :users}
    add_reference :lightek_commerce_orders, :gatekeeper_application_launch, foreign_key: true
    create_table :hosting_packages do |t|
      t.references :product, null: false, foreign_key: {to_table: :lightek_commerce_products}, index: {unique: true}
      t.references :compute_provider, null: false, foreign_key: true
      t.references :gatekeeper_application_template, null: false, foreign_key: true, index: {name: "idx_hosting_package_template"}
      t.string :region, null: false
      t.string :provider_plan, null: false
      t.integer :monthly_cost_ceiling_cents, null: false
      t.integer :minimum_margin_cents, default: 1, null: false
      t.boolean :active, default: false, null: false
      t.timestamps
    end
    create_table :lightek_commerce_subscriptions do |t|
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true}
      t.string :processor_reference, null: false, index: {unique: true}
      t.string :customer_reference
      t.string :status, null: false, default: "incomplete"
      t.string :billing_interval, null: false
      t.boolean :cancel_at_period_end, default: false, null: false
      t.integer :amount_cents, null: false
      t.string :currency, default: "usd", null: false
      t.datetime :current_period_end
      t.datetime :last_event_at
      t.references :bank_subscription, foreign_key: {to_table: :dymond_bank_subscriptions}, index: {name: "idx_commerce_bank_subscription"}
      t.timestamps
    end
    create_table :lightek_commerce_billing_invoices do |t|
      t.references :subscription, null: false, foreign_key: {to_table: :lightek_commerce_subscriptions}, index: {name: "idx_billing_invoice_subscription"}
      t.string :processor_reference, null: false, index: {unique: true}
      t.references :settlement_order, foreign_key: {to_table: :lightek_commerce_orders}, index: {unique: true, name: "idx_billing_invoice_settlement"}
      t.integer :amount_paid_cents, null: false
      t.string :currency, null: false
      t.datetime :paid_at, null: false
      t.timestamps
    end
  end
end
