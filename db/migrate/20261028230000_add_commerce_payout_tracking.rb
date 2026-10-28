class AddCommercePayoutTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :merchant_transfer_ref, :string
    add_column :lightek_commerce_orders, :merchant_transfer_amount_cents, :integer
    add_column :lightek_commerce_orders, :merchant_transfer_requested_at, :datetime
    add_column :lightek_commerce_orders, :merchant_transfer_completed_at, :datetime
    add_column :lightek_commerce_orders, :merchant_transfer_error, :text
    add_index :lightek_commerce_orders, :merchant_transfer_ref, unique: true
  end
end
