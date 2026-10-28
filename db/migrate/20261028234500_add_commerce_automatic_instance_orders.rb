class AddCommerceAutomaticInstanceOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_products, :subscription_plan_id, :bigint
    add_column :lightek_commerce_orders, :provisioning_request_id, :bigint
    add_column :lightek_commerce_orders, :provisioning_state, :string
    add_column :lightek_commerce_orders, :provisioning_error, :text
    add_column :lightek_commerce_orders, :provisioned_at, :datetime
    add_index :lightek_commerce_orders, :provisioning_request_id
    add_index :lightek_commerce_products, :subscription_plan_id
  end
end
