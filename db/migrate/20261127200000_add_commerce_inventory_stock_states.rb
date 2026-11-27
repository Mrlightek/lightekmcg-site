class AddCommerceInventoryStockStates < ActiveRecord::Migration[8.0]
  def change
    %i[lightek_commerce_products lightek_commerce_product_variants].each do |table|
      %i[incoming_quantity unavailable_quantity damaged_quantity].each do |column|
        add_column table, column, :integer, default: 0, null: false
      end
      add_check_constraint table, 'incoming_quantity >= 0 AND unavailable_quantity >= 0 AND damaged_quantity >= 0',
        name: 'commerce_stock_states_nonnegative'
    end
    add_column :lightek_commerce_inventory_changes, :stock_state, :string, default: 'available', null: false
    remove_check_constraint :lightek_commerce_inventory_changes,
      "(source IN ('csv_import', 'product_editor') AND actor_id IS NOT NULL AND order_id IS NULL) OR " \
      "(source IN ('checkout_reserved', 'checkout_released') AND actor_id IS NULL AND order_id IS NOT NULL)",
      name: 'commerce_inventory_change_context'
    add_check_constraint :lightek_commerce_inventory_changes,
      "(source IN ('csv_import', 'product_editor', 'stock_state_adjustment') AND actor_id IS NOT NULL AND order_id IS NULL) OR " \
      "(source IN ('checkout_reserved', 'checkout_released') AND actor_id IS NULL AND order_id IS NOT NULL)",
      name: 'commerce_inventory_change_context'
    add_check_constraint :lightek_commerce_inventory_changes,
      "stock_state = 'available' OR (source = 'stock_state_adjustment' AND stock_state IN ('incoming', 'unavailable', 'damaged'))",
      name: 'commerce_inventory_change_stock_state'
  end
end
