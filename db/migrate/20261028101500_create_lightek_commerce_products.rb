class CreateLightekCommerceProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_products do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :name, null: false, limit: 160
      t.string :slug, null: false, limit: 180
      t.text :description
      t.integer :price_cents, null: false, default: 0
      t.string :currency, null: false, default: "usd", limit: 3
      t.integer :inventory_quantity, null: false, default: 0
      t.boolean :published, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_commerce_products, [:site_id, :slug], unique: true
    add_check_constraint :lightek_commerce_products, "price_cents >= 0", name: "commerce_price_nonnegative"
    add_check_constraint :lightek_commerce_products, "inventory_quantity >= 0", name: "commerce_inventory_nonnegative"
  end
end
