# frozen_string_literal: true

class CreateLightekSalesSocialProspects < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_sales_social_prospects do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :lead, foreign_key: {to_table: :lightek_sales_leads}
      t.references :saved_by, null: false, foreign_key: {to_table: :users}
      t.references :contacted_by, foreign_key: {to_table: :users}
      t.string :provider, null: false
      t.string :remote_id, null: false
      t.string :source_post_id, null: false
      t.string :sender_id, null: false
      t.string :outreach_status, default: 'ready', null: false
      t.string :provider_message_id
      t.string :contact_permission
      t.datetime :contacted_at
      t.datetime :contact_blocked_at
      t.timestamps

      t.index %i[site_id provider remote_id], unique: true, name: 'idx_lightek_sales_social_prospect_identity'
    end
  end
end
