class AddCommerceFulfillmentTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_commerce_orders, :fulfilled_at, :datetime
    add_column :lightek_commerce_orders, :fulfillment_reference, :string, limit: 160
    add_column :lightek_commerce_orders, :fulfillment_note, :text
    add_column :lightek_commerce_orders, :fulfillment_notification_sent_at, :datetime
  end
end
