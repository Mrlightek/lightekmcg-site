class AddMerchandisingToMarketplaceListings < ActiveRecord::Migration[8.0]
  def change
    add_column :dymond_catalog_marketplace_listings, :marketing_headline, :string, limit: 180
    add_column :dymond_catalog_marketplace_listings, :marketing_subheadline, :text
    add_column :dymond_catalog_marketplace_listings, :best_for, :string, limit: 160
    add_column :dymond_catalog_marketplace_listings, :plan_badge, :string, limit: 50
    add_column :dymond_catalog_marketplace_listings, :cta_label, :string, limit: 60
    add_column :dymond_catalog_marketplace_listings, :fulfillment_summary, :text
    add_column :dymond_catalog_marketplace_listings, :marketing_features, :jsonb, null: false, default: []
    add_column :dymond_catalog_marketplace_listings, :marketing_faq, :jsonb, null: false, default: []
  end
end
