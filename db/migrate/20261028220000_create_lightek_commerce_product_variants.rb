class CreateLightekCommerceProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_product_variants do |t|
      t.references :product, null: false, foreign_key: {to_table: :lightek_commerce_products}
      t.string :name, null: false
      t.string :sku
      t.integer :price_cents, null: false
      t.integer :inventory_quantity, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :lightek_commerce_product_variants, [:product_id, :sku], unique: true, where: "sku IS NOT NULL", name: "index_commerce_variants_product_sku"
    add_reference :lightek_commerce_order_items, :variant, foreign_key: {to_table: :lightek_commerce_product_variants}, null: true
  end
end
