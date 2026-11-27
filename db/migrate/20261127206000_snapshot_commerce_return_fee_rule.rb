class SnapshotCommerceReturnFeeRule < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_merchandise_returns, :suggested_refund_fee_cents, :integer, null: false, default: 0
    add_check_constraint :lightek_commerce_merchandise_returns, 'suggested_refund_fee_cents >= 0',
      name: 'commerce_merchandise_suggested_fee'
  end
end
