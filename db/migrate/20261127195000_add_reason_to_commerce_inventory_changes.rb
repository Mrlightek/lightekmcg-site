class AddReasonToCommerceInventoryChanges < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_inventory_changes, :reason, :string
    add_check_constraint :lightek_commerce_inventory_changes,
      "reason IS NULL OR (source IN ('csv_import', 'product_editor') AND " \
      "reason IN ('count', 'received', 'returned', 'damaged', 'lost', 'correction'))",
      name: 'commerce_inventory_change_reason'
  end
end
