class AllowPreReceiptCommerceExchanges < ActiveRecord::Migration[8.0]
  TABLE = :lightek_commerce_merchandise_returns
  CONSTRAINT = 'commerce_merchandise_exchange_state'

  def up
    remove_check_constraint TABLE, name: CONSTRAINT
    add_check_constraint TABLE, <<~SQL.squish, name: CONSTRAINT
      exchange_status IS NULL OR (
        refund_fee_cents = 0 AND replacement_name IS NOT NULL AND (
          (exchange_status = 'reserved' AND status IN ('approved', 'received') AND exchange_shipped_at IS NULL AND exchange_shipping_reference IS NULL)
          OR (exchange_status = 'canceled' AND status IN ('approved', 'received', 'canceled') AND exchange_shipped_at IS NULL AND exchange_shipping_reference IS NULL)
          OR (exchange_status = 'shipped' AND status = 'received' AND exchange_shipped_at IS NOT NULL AND exchange_shipping_reference IS NOT NULL)
        )
      )
    SQL
  end

  def down
    if select_value("SELECT 1 FROM #{TABLE} WHERE exchange_status IS NOT NULL AND status <> 'received' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, 'Resolve pre-receipt exchange records before rolling back this constraint.'
    end

    remove_check_constraint TABLE, name: CONSTRAINT
    add_check_constraint TABLE, <<~SQL.squish, name: CONSTRAINT
      exchange_status IS NULL OR (status = 'received' AND refund_fee_cents = 0 AND replacement_name IS NOT NULL AND
        ((exchange_status IN ('reserved', 'canceled') AND exchange_shipped_at IS NULL AND exchange_shipping_reference IS NULL)
        OR (exchange_status = 'shipped' AND exchange_shipped_at IS NOT NULL AND exchange_shipping_reference IS NOT NULL)))
    SQL
  end
end
