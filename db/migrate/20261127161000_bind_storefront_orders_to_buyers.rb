# frozen_string_literal: true

class BindStorefrontOrdersToBuyers < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :storefront_buyer_id, :bigint
    add_index :lightek_commerce_orders, [:site_id, :storefront_buyer_id], name: 'idx_commerce_orders_storefront_buyer'
  end
end
