# frozen_string_literal: true

class AddCommerceQuantityPromotions < ActiveRecord::Migration[8.0]
  def change
    change_table :lightek_commerce_discounts do |t|
      t.references :qualifying_product, foreign_key: {to_table: :lightek_commerce_products}, index: false
      t.references :qualifying_collection, foreign_key: {to_table: :lightek_commerce_collections}, index: false
      t.integer :buy_quantity
      t.integer :get_quantity
      t.integer :applications_per_order
      t.string :reward_type
    end
  end
end
