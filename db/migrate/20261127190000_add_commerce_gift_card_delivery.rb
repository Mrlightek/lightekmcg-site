# frozen_string_literal: true

class AddCommerceGiftCardDelivery < ActiveRecord::Migration[8.0]
  def change
    change_table :lightek_commerce_orders do |t|
      t.string :gift_recipient_email
      t.datetime :gift_deliver_at
      t.datetime :gift_delivered_at
    end
  end
end
