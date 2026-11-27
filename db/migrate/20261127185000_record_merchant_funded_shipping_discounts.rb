# frozen_string_literal: true

class RecordMerchantFundedShippingDiscounts < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :shipping_discount_cents, :integer, default: 0, null: false
    add_check_constraint :lightek_commerce_orders, 'shipping_discount_cents >= 0',
      name: 'commerce_shipping_discount_nonnegative'
  end
end
