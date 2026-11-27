class AddCommerceReturnFee < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_merchandise_returns, :refund_fee_cents, :integer, null: false, default: 0
    add_check_constraint :lightek_commerce_merchandise_returns,
      "refund_fee_cents >= 0 AND (refund_fee_cents = 0 OR status IN ('approved', 'received', 'canceled'))",
      name: 'commerce_merchandise_return_fee'
  end
end
