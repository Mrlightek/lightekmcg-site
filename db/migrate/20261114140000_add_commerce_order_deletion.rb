class AddCommerceOrderDeletion < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :deleted_at, :datetime
    add_index :lightek_commerce_orders, [:site_id, :deleted_at], name: "idx_commerce_visible_orders"
  end
end
