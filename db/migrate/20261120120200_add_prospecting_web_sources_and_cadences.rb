# frozen_string_literal: true

class AddProspectingWebSourcesAndCadences < ActiveRecord::Migration[8.0]
  def change
    change_column_null :lightek_sales_social_prospects, :source_post_id, true
    add_column :lightek_sales_social_prospects, :web_profile_url, :string
    add_column :lightek_sales_social_prospects, :web_source_url, :string
    add_column :lightek_sales_social_prospects, :web_display_name, :string
    add_index :lightek_sales_social_prospects, %i[site_id provider web_profile_url], unique: true,
      where: 'web_profile_url IS NOT NULL', name: 'idx_sales_prospect_web_profile'

    create_table :lightek_sales_prospecting_cadences do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :name, null: false
      t.json :steps, null: false
      t.timestamps

      t.index %i[site_id name], unique: true, name: 'idx_sales_prospecting_cadence_name'
    end
  end
end
