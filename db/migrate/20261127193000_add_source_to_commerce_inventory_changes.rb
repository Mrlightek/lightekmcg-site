class AddSourceToCommerceInventoryChanges < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_inventory_changes, :source, :string, default: 'csv_import', null: false
    add_check_constraint :lightek_commerce_inventory_changes, "source IN ('csv_import', 'product_editor')",
      name: 'commerce_inventory_change_source'
  end
end
