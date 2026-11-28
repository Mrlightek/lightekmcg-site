class CreateCommerceInventoryAdjustments < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_inventory_changes do |t|
      t.bigint :site_id, null: false
      t.bigint :product_id, null: false
      t.bigint :variant_id
      t.bigint :actor_id, null: false
      t.string :actor_name, null: false
      t.string :product_name, null: false
      t.string :variant_name
      t.string :batch_key, null: false
      t.integer :before_quantity, null: false
      t.integer :after_quantity, null: false
      t.datetime :created_at, null: false
      t.index [:site_id, :id], name: 'idx_commerce_inventory_changes_site_history'
      t.check_constraint 'before_quantity >= 0 AND after_quantity >= 0 AND before_quantity <> after_quantity',
        name: 'commerce_inventory_change_counts'
    end
  end
end
