class AddClientCheckoutKeyToCommerceOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :client_checkout_key, :string, limit: 64
    add_index :lightek_commerce_orders, [:customer_email, :client_checkout_key], unique: true,
      where: "client_checkout_key IS NOT NULL", name: "idx_commerce_client_checkout_key"
  end
end
