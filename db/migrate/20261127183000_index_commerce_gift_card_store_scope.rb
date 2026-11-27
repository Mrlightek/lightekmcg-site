# frozen_string_literal: true

class IndexCommerceGiftCardStoreScope < ActiveRecord::Migration[8.0]
  def change
    add_index :lightek_commerce_gift_cards, [:store_scope, :livemode], name: 'idx_commerce_gift_cards_scope_mode'
  end
end
