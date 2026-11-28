class RecordOrderInventoryChanges < ActiveRecord::Migration[8.0]
  def change
    change_column_null :lightek_commerce_inventory_changes, :actor_id, true
    add_column :lightek_commerce_inventory_changes, :order_id, :bigint
    remove_check_constraint :lightek_commerce_inventory_changes, "source IN ('csv_import', 'product_editor')",
      name: 'commerce_inventory_change_source'
    add_check_constraint :lightek_commerce_inventory_changes,
      "(source IN ('csv_import', 'product_editor') AND actor_id IS NOT NULL AND order_id IS NULL) OR " \
      "(source IN ('checkout_reserved', 'checkout_released') AND actor_id IS NULL AND order_id IS NOT NULL)",
      name: 'commerce_inventory_change_context'
  end
end
