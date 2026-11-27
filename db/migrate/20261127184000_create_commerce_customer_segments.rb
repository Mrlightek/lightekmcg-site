# frozen_string_literal: true

class CreateCommerceCustomerSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_customer_segments do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}, index: false
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :minimum_orders
      t.integer :maximum_orders
      t.bigint :minimum_net_spend_cents
      t.timestamps
      t.index [:site_id, :slug], unique: true, name: 'idx_commerce_customer_segments_site_slug'
    end

    add_reference :lightek_commerce_discounts, :customer_segment,
      foreign_key: {to_table: :lightek_commerce_customer_segments}, index: {name: 'idx_commerce_discounts_segment'}
    add_index :lightek_commerce_orders, [:site_id, :storefront_buyer_id], name: 'idx_commerce_orders_store_buyer'
  end
end
