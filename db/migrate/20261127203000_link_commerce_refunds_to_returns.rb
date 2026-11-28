class LinkCommerceRefundsToReturns < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_refunds, :merchandise_return_id, :bigint
    add_index :lightek_commerce_refunds, :merchandise_return_id, unique: true, name: 'idx_commerce_refund_return'
    add_foreign_key :lightek_commerce_refunds, :lightek_commerce_merchandise_returns, column: :merchandise_return_id
  end
end
