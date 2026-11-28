class LinkReturnShippingQuotes < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_shipping_quotes, :merchandise_return, index: {name: 'idx_shipping_quotes_return'},
      foreign_key: {to_table: :lightek_commerce_merchandise_returns}
    add_reference :lightek_commerce_merchandise_returns, :return_shipping_quote, index: {unique: true, name: 'idx_return_shipping_quote'},
      foreign_key: {to_table: :lightek_shipping_quotes}
  end
end
