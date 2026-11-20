# frozen_string_literal: true

class AddGoogleMapsBusinessProspectFields < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_sales_social_prospects, :business_website_url, :string
    add_column :lightek_sales_social_prospects, :website_finding, :text
  end
end
