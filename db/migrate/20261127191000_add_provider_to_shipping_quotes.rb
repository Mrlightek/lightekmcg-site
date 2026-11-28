# frozen_string_literal: true

class AddProviderToShippingQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_shipping_quotes, :provider, :string, null: false, default: 'fedex'
  end
end
