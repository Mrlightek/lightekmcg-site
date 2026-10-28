class ExpandLightekCommerceProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_products, :image_url, :string, limit: 1200
    add_column :lightek_commerce_products, :sku, :string, limit: 100
    add_column :lightek_commerce_products, :product_type, :string, null: false, default: "physical"
    add_column :lightek_commerce_products, :short_description, :string, limit: 300
    add_column :lightek_commerce_products, :compare_at_cents, :integer
    add_column :lightek_commerce_products, :featured, :boolean, default: false, null: false
    add_index :lightek_commerce_products, [:site_id, :sku], unique: true, where: "sku IS NOT NULL", name: "idx_commerce_site_sku"
    add_check_constraint :lightek_commerce_products, "compare_at_cents IS NULL OR compare_at_cents >= 0", name: "commerce_compare_price_valid"
  end
end
