class CreateCommerceMerchandiseReturns < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_merchandise_returns do |t|
      t.bigint :order_id, null: false
      t.bigint :order_item_id, null: false
      t.string :request_key, limit: 36, null: false
      t.integer :quantity, null: false
      t.string :reason, limit: 300, null: false
      t.string :status, default: 'requested', null: false
      t.string :disposition
      t.bigint :requested_by_id, null: false
      t.bigint :resolved_by_id
      t.datetime :received_at
      t.timestamps
      t.index [:order_id, :request_key], unique: true, name: 'idx_commerce_merchandise_return_request'
      t.index [:order_item_id, :status], name: 'idx_commerce_merchandise_return_item'
      t.check_constraint "quantity > 0 AND status IN ('requested', 'approved', 'rejected', 'received', 'canceled')",
        name: 'commerce_merchandise_return_valid'
      t.check_constraint "(status = 'received' AND disposition IS NOT NULL AND " \
        "disposition IN ('available', 'damaged', 'discarded') AND received_at IS NOT NULL) OR " \
        "(status <> 'received' AND disposition IS NULL AND received_at IS NULL)",
        name: 'commerce_merchandise_return_receipt'
    end
    add_column :lightek_commerce_inventory_changes, :merchandise_return_id, :bigint
    add_check_constraint :lightek_commerce_inventory_changes,
      "merchandise_return_id IS NULL OR (source = 'stock_state_adjustment' AND " \
      "stock_state IN ('available', 'damaged') AND supplier_order_id IS NULL)",
      name: 'commerce_inventory_change_return'
  end
end
