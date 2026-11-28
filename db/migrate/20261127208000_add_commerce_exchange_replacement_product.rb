class AddCommerceExchangeReplacementProduct < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_commerce_merchandise_returns, :replacement_product, index: {name: 'idx_commerce_exchange_product'},
      foreign_key: {to_table: :lightek_commerce_products}
  end
end
