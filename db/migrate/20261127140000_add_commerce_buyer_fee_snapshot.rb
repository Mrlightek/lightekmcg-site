# frozen_string_literal: true

class AddCommerceBuyerFeeSnapshot < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :buyer_fee_snapshot, :jsonb, default: {}, null: false
    add_column :lightek_commerce_orders, :buyer_fee_transfer_destination, :string
    add_column :lightek_commerce_orders, :buyer_fee_reversal_requested_at, :datetime
    add_column :lightek_commerce_orders, :buyer_fee_reversal_ref, :string
  end
end
