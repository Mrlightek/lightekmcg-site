# frozen_string_literal: true

class ExtendCommerceDiscountRules < ActiveRecord::Migration[8.0]
  def change
    change_table :lightek_commerce_discounts do |t|
      t.boolean :combinable, null: false, default: false
      t.references :target_product, foreign_key: {to_table: :lightek_commerce_products}, index: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.integer :usage_limit
      t.integer :buyer_limit
    end

    create_table :lightek_commerce_discount_uses do |t|
      t.references :discount, null: false, foreign_key: {to_table: :lightek_commerce_discounts}, index: false
      t.references :order, null: false, foreign_key: {to_table: :lightek_commerce_orders}
      t.bigint :buyer_id
      t.integer :amount_cents, null: false
      t.index [:order_id, :discount_id], unique: true, name: "idx_commerce_discount_uses_order_rule"
      t.index [:discount_id, :buyer_id], name: "idx_commerce_discount_uses_rule_buyer"
    end
  end
end
