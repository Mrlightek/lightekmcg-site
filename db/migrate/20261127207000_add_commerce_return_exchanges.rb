class AddCommerceReturnExchanges < ActiveRecord::Migration[8.0]
  def change
    change_table :lightek_commerce_merchandise_returns do |t|
      t.string :exchange_status
      t.bigint :replacement_variant_id
      t.string :replacement_name
      t.string :exchange_shipping_reference, limit: 120
      t.datetime :exchange_shipped_at
    end
    add_check_constraint :lightek_commerce_merchandise_returns,
      "exchange_status IS NULL OR (status = 'received' AND refund_fee_cents = 0 AND replacement_name IS NOT NULL AND " \
      "((exchange_status IN ('reserved', 'canceled') AND exchange_shipped_at IS NULL AND exchange_shipping_reference IS NULL) OR " \
      "(exchange_status = 'shipped' AND exchange_shipped_at IS NOT NULL AND exchange_shipping_reference IS NOT NULL)))",
      name: 'commerce_merchandise_exchange_state'
  end
end
