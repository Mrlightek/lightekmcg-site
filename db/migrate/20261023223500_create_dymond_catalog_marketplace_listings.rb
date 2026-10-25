class CreateDymondCatalogMarketplaceListings < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_catalog_marketplace_listings do |t|
      t.bigint :offer_id, null: false
      t.string :title, null: false
      t.text :summary
      t.string :category, null: false
      t.boolean :published, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :dymond_catalog_marketplace_listings, :offer_id, unique: true
    add_index :dymond_catalog_marketplace_listings, [:published, :category, :position], name: "idx_marketplace_merchandising"
    add_foreign_key :dymond_catalog_marketplace_listings, :dymond_bank_offers, column: :offer_id
  end
end
