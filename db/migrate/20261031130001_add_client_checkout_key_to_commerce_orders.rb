# Both colliding migrations receive new versions: an old 130000 record cannot
# tell Rails whether checkout or Studio was applied on this database.
class AddClientCheckoutKeyToCommerceOrders < ActiveRecord::Migration[8.0]
  def up
    add_column :lightek_commerce_orders, :client_checkout_key, :string, limit: 64 unless column_exists?(:lightek_commerce_orders, :client_checkout_key)
    unless index_exists?(:lightek_commerce_orders, [:customer_email, :client_checkout_key], name: "idx_commerce_client_checkout_key")
      add_index :lightek_commerce_orders, [:customer_email, :client_checkout_key], unique: true,
        where: "client_checkout_key IS NOT NULL", name: "idx_commerce_client_checkout_key"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reconciliation preserves schema that may have existed under version 20261031130000"
  end
end
