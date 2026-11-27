# frozen_string_literal: true

class CreateCommerceCollections < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_commerce_collections do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}, index: false
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :published, null: false, default: false
      t.string :source, null: false, default: 'manual'
      t.string :matching, null: false, default: 'all'
      t.json :product_ids, null: false, default: []
      t.json :conditions, null: false, default: []
      t.timestamps
      t.index [:site_id, :slug], unique: true, name: 'idx_commerce_collections_site_slug'
    end
    add_reference :lightek_commerce_discounts, :target_collection,
      foreign_key: {to_table: :lightek_commerce_collections}, index: false
  end
end
