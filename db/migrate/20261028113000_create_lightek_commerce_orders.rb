class CreateLightekCommerceOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_orders do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :status, null: false, default: "pending_payment"
      t.string :customer_email, null: false
      t.string :currency, null: false, default: "usd"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :payment_provider
      t.string :payment_reference
      t.datetime :paid_at
      t.datetime :canceled_at
      t.timestamps
    end
    add_index :lightek_commerce_orders, [:site_id, :payment_reference], unique: true, where: "payment_reference IS NOT NULL", name: "idx_commerce_payment_reference"
    create_table :lightek_commerce_order_items do |t|
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}
      t.references :product, null: false, foreign_key: {to_table: :lightek_commerce_products}
      t.string :name, null: false
      t.integer :quantity, null: false
      t.integer :unit_price_cents, null: false
      t.integer :line_total_cents, null: false
      t.timestamps
    end
    add_check_constraint :lightek_commerce_order_items, "quantity > 0 AND unit_price_cents >= 0 AND line_total_cents >= 0", name: "commerce_item_amounts_valid"
    add_check_constraint :lightek_commerce_orders, "subtotal_cents >= 0 AND shipping_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0", name: "commerce_order_amounts_valid"
  end
end
