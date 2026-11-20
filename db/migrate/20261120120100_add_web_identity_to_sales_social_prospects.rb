# frozen_string_literal: true

class AddWebIdentityToSalesSocialProspects < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_sales_social_prospects, :web_username, :string
    change_column_null :lightek_sales_social_prospects, :remote_id, true
    change_column_null :lightek_sales_social_prospects, :sender_id, true
    add_index :lightek_sales_social_prospects, %i[site_id provider web_username], unique: true,
      where: 'web_username IS NOT NULL', name: 'idx_lightek_sales_social_prospect_web_identity'
  end
end
