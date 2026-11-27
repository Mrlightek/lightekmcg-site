# frozen_string_literal: true

class AddCommerceDiscounts < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_discounts do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :name, null: false
      t.string :code
      t.string :kind, null: false
      t.integer :amount, null: false
      t.integer :minimum_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [:site_id, :code], unique: true
    end
    add_column :lightek_commerce_orders, :discount_cents, :integer, null: false, default: 0
    add_column :lightek_commerce_orders, :discount_name, :string
  end
end
