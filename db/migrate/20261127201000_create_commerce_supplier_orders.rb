class CreateCommerceSupplierOrders < ActiveRecord::Migration[8.0]
  def change
    %i[lightek_commerce_products lightek_commerce_product_variants].each do |table|
      add_column table, :supplier_incoming_quantity, :integer, default: 0, null: false
      add_check_constraint table, 'supplier_incoming_quantity >= 0 AND supplier_incoming_quantity <= incoming_quantity',
        name: 'commerce_supplier_incoming_valid'
    end
    create_table :lightek_commerce_supplier_orders do |t|
      t.references :site, null: false, index: false
      t.string :supplier, limit: 160, null: false
      t.string :status, default: 'draft', null: false
      t.date :expected_on
      t.string :invoice_reference, limit: 160
      t.bigint :invoice_subtotal_cents
      t.timestamps
      t.index [:site_id, :id], name: 'idx_supplier_orders_by_store'
      t.check_constraint "status IN ('draft', 'ordered', 'received', 'canceled')", name: 'commerce_supplier_order_status'
    end
    create_table :lightek_commerce_supplier_order_lines do |t|
      t.references :supplier_order, null: false, index: {name: 'idx_supplier_order_lines'},
        foreign_key: {to_table: :lightek_commerce_supplier_orders}
      t.bigint :product_id, null: false
      t.bigint :variant_id
      t.string :item_name, null: false
      t.integer :ordered_quantity, null: false
      t.integer :received_quantity, default: 0, null: false
      t.bigint :unit_cost_cents, null: false
      t.timestamps
      t.check_constraint 'ordered_quantity > 0 AND received_quantity >= 0 AND received_quantity <= ordered_quantity AND unit_cost_cents >= 0',
        name: 'commerce_supplier_line_amounts'
    end
    add_column :lightek_commerce_inventory_changes, :supplier_order_id, :bigint
    add_check_constraint :lightek_commerce_inventory_changes,
      "supplier_order_id IS NULL OR (source = 'stock_state_adjustment' AND stock_state IN ('available', 'incoming'))",
      name: 'commerce_inventory_change_supplier'
  end
end
