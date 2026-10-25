class AddConfigurationToMarketplaceListings < ActiveRecord::Migration[8.0]
  def change
    add_column :dymond_catalog_marketplace_listings, :configuration, :jsonb, default: {}, null: false
  end
end
